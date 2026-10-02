class_name EnvironmentGenerationPass
extends Node

const PHASE := "environment"
const GENERATED_GROUP := &"generated_environment_object"
const FOREST_FORBIDDEN := WorldOccupancyMap.ROAD | WorldOccupancyMap.WATER | WorldOccupancyMap.POI | WorldOccupancyMap.BUILDING | WorldOccupancyMap.RUIN | WorldOccupancyMap.NO_SPAWN

@export var enabled := true
@export var profile: EnvironmentGenerationProfile
@export var poi_pass_path: NodePath = NodePath("../PoiPlacementPass")
@export var world_seed_source_path: NodePath = NodePath("../ChunkWorldGenerator")

var candidates: Array[Dictionary] = []
var accepted: Array[Dictionary] = []
var rejections: Array[Dictionary] = []
var _generated := false
var _owned_claims: Array[String] = []
var _owned_tiles := {}
var blocking_errors: Array[String] = []
var _reverse_chunk_enumeration_for_test := false
var _finite_chunks_generated: Array[Vector2i] = []
var _scene_entry_validity := {}
var _forest_cells := {}
var _forest_land_cells := 0
var _accepted_counts := {}
var _accepted_world_counts := {}

func get_generation_phase() -> String: return PHASE
func has_generation_pending() -> bool: return enabled and not _generated
func get_generation_compatibility_profile() -> Dictionary: return profile.compatibility_profile() if profile != null else {"id":"environment:missing"}

func _prepare_generation() -> PoiPlacementPass:
	if not enabled: return null
	_generated = false
	blocking_errors.clear()
	_scene_entry_validity.clear()
	var check := profile.validate() if profile != null else {"valid":false, "errors":["MISSING_PROFILE"]}
	if not bool(check.valid):
		_blocking("<profile>", "<none>", "VALIDATION", ";".join(check.errors))
		return null
	var poi := get_node_or_null(poi_pass_path) as PoiPlacementPass
	if poi == null or poi.occupancy.bounds.size == Vector2i.ZERO:
		_blocking("<occupancy>", "<none>", "MISSING_OCCUPANCY", "occupancy unavailable")
		return null
	_clear_generated()
	return poi

func _sort_candidates() -> void:
	if profile.forest_enabled:
		for candidate in candidates:
			candidate["resolution_score"] = WorldSeedService.derive_seed(_resolve_master_seed(), "environment/competition/" + String(candidate.entry_id), [candidate.cell.x, candidate.cell.y])
	candidates.sort_custom(_candidate_less)

func _candidate_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a.priority) != int(b.priority): return int(a.priority) < int(b.priority)
	if int(a.get("resolution_score", 0)) != int(b.get("resolution_score", 0)): return int(a.resolution_score) < int(b.resolution_score)
	return String(a.candidate_id) < String(b.candidate_id)

func _sort_candidates_async(budget_usec: int) -> void:
	var started := Time.get_ticks_usec()
	var seed := _resolve_master_seed()
	if profile.forest_enabled:
		for candidate in candidates:
			candidate["resolution_score"] = WorldSeedService.derive_seed(seed, "environment/competition/" + String(candidate.entry_id), [candidate.cell.x, candidate.cell.y])
			if Time.get_ticks_usec() - started >= budget_usec:
				await get_tree().process_frame
				started = Time.get_ticks_usec()
	# Bottom-up merge sort can yield without changing the comparison order contract.
	var scratch: Array[Dictionary] = candidates.duplicate()
	var width := 1
	var count := candidates.size()
	while width < count:
		for first in range(0, count, width * 2):
			var middle := mini(first + width, count)
			var last := mini(first + width * 2, count)
			var left := first
			var right := middle
			for index in range(first, last):
				if left < middle and (right >= last or not _candidate_less(candidates[right], candidates[left])):
					scratch[index] = candidates[left]
					left += 1
				else:
					scratch[index] = candidates[right]
					right += 1
				if Time.get_ticks_usec() - started >= budget_usec:
					await get_tree().process_frame
					started = Time.get_ticks_usec()
		var previous := candidates
		candidates = scratch
		scratch = previous
		width *= 2


func run_generation_pass() -> void:
	var poi := _prepare_generation()
	if poi == null: return
	_build_forest(poi.occupancy, _resolve_master_seed())
	_build_candidates(poi.occupancy.bounds, _resolve_master_seed())
	_sort_candidates()
	for candidate in candidates:
		_resolve(candidate, poi.occupancy)
	_generated = true

## Same ordered candidates and RNG as the editor path, with a wall-clock frame budget.
func run_generation_pass_async(frame_budget_ms: float = 6.0) -> void:
	var poi := _prepare_generation()
	if poi == null: return
	var seed := _resolve_master_seed()
	_build_forest(poi.occupancy, seed)
	var budget_usec := maxi(1000, int(frame_budget_ms * 1000.0))
	var started := Time.get_ticks_usec()
	var work := _candidate_work(poi.occupancy.bounds)
	for job in work:
		_build_entry_chunk_candidates(poi.occupancy.bounds, seed, _resolve_chunk_size_tiles(), job.chunk, job.entry)
		if Time.get_ticks_usec() - started >= budget_usec:
			await get_tree().process_frame
			started = Time.get_ticks_usec()
	await _sort_candidates_async(budget_usec)
	await get_tree().process_frame
	started = Time.get_ticks_usec()
	for candidate in candidates:
		_resolve(candidate, poi.occupancy)
		if Time.get_ticks_usec() - started >= budget_usec:
			await get_tree().process_frame
			started = Time.get_ticks_usec()
	_generated = true

func _build_candidates(bounds: Rect2i, master_seed: int) -> void:
	for job in _candidate_work(bounds):
		_build_entry_chunk_candidates(bounds, master_seed, _resolve_chunk_size_tiles(), job.chunk, job.entry)

func _candidate_work(bounds: Rect2i) -> Array[Dictionary]:
	var work: Array[Dictionary] = []
	candidates.clear(); accepted.clear(); rejections.clear()
	_accepted_counts.clear()
	_accepted_world_counts.clear()
	var chunk_size := _resolve_chunk_size_tiles()
	var chunks := _finite_chunks(bounds, chunk_size)
	_finite_chunks_generated = chunks.duplicate()
	if _reverse_chunk_enumeration_for_test:
		chunks.reverse()
	var entries: Array[EnvironmentEntry] = []
	for entry in profile.entries:
		if entry != null and entry.enabled: entries.append(entry)
	entries.sort_custom(func(a, b): return a.entry_id < b.entry_id)
	for entry in entries:
		for chunk in chunks:
			work.append({"chunk": chunk, "entry": entry})
	return work

func _build_entry_chunk_candidates(bounds: Rect2i, master_seed: int, chunk_size: int, chunk: Vector2i, entry: EnvironmentEntry) -> void:
	if entry.chunk_spawn_probability < 1.0:
		var chance := posmod(WorldSeedService.derive_seed(master_seed, "environment/chunk-presence/" + entry.entry_id, [chunk.x, chunk.y]), 1000000)
		if chance >= int(entry.chunk_spawn_probability * 1000000.0): return
	var chunk_bounds := Rect2i(chunk * chunk_size, Vector2i(chunk_size, chunk_size)).intersection(bounds)
	var ranked: Array[Dictionary] = []
	var density_candidates: Array[Dictionary] = []
	var chunk_seed := WorldSeedService.derive_seed(master_seed, "environment/chunk/" + entry.entry_id, [chunk.x, chunk.y])
	for y in range(chunk_bounds.position.y, chunk_bounds.end.y):
		for x in range(chunk_bounds.position.x, chunk_bounds.end.x):
			var cell := Vector2i(x, y)
			if profile.forest_enabled and entry.category == "trees" and not _forest_cells.has(cell): continue
			var score := posmod(WorldSeedService.derive_seed(chunk_seed, "candidate", [x, y]), 1000000)
			var record := {"cell":cell, "score":score}
			ranked.append(record)
			if score < int(entry.density * 1000000.0): density_candidates.append(record)
	ranked.sort_custom(func(a, b): return _ranked_cell_less(a, b))
	density_candidates.sort_custom(func(a, b): return _ranked_cell_less(a, b))
	var selected := {}
	for record in density_candidates:
		if selected.size() >= entry.candidate_budget_per_chunk_value(): break
		selected[Vector2i(record.cell)] = true
	var values: Array[Vector2i] = []
	for cell in selected.keys(): values.append(cell as Vector2i)
	values.sort_custom(func(a, b): return _candidate_id(chunk, entry.entry_id, a) < _candidate_id(chunk, entry.entry_id, b))
	for cell in values:
		candidates.append({"candidate_id":_candidate_id(chunk, entry.entry_id, cell), "entry_id":entry.entry_id, "chunk":chunk, "cell":cell, "priority":_resolution_priority(entry, false), "quota_fallback":false, "status":"", "accepted":false})
	var remaining := entry.candidate_budget_per_chunk_value() - values.size()
	if entry.min_instances_per_chunk > 0 and remaining > 0:
		for record in ranked:
			if remaining <= 0: break
			var fallback_cell := record.cell as Vector2i
			if selected.has(fallback_cell): continue
			candidates.append({"candidate_id":_candidate_id(chunk, entry.entry_id, fallback_cell), "entry_id":entry.entry_id, "chunk":chunk, "cell":fallback_cell, "priority":_resolution_priority(entry, true), "quota_fallback":true, "status":"", "accepted":false})
			remaining -= 1

func _resolve(candidate: Dictionary, occupancy: WorldOccupancyMap) -> void:
	var entry := _entry_by_id(String(candidate.entry_id))
	if entry == null:
		_reject(candidate, "MISSING_ENTRY"); return
	var cell: Vector2i = candidate.cell
	var chunk := candidate.chunk as Vector2i
	if entry.near_structure_radius_cells > 0.0:
		var nearby := false
		for item in accepted:
			if item.category == "structures" and Vector2(cell).distance_to(Vector2(item.cell)) <= entry.near_structure_radius_cells:
				nearby = true
				break
		if not nearby: _reject(candidate, "no_nearby_structure"); return
	if entry.max_instances_per_world > 0 and int(_accepted_world_counts.get(entry.entry_id, 0)) >= entry.max_instances_per_world:
		_reject(candidate, "max_instances_per_world"); return
	if bool(candidate.get("quota_fallback", false)) and _accepted_for_entry_in_chunk(entry.entry_id, chunk) >= entry.min_instances_per_chunk:
		_reject(candidate, "min_instances_per_chunk_satisfied")
		return
	if _accepted_for_entry_in_chunk(entry.entry_id, chunk) >= entry.max_instances_per_chunk_value():
		_reject(candidate, "max_instances_per_chunk")
		return
	var footprint := _footprint(cell, entry)
	if entry.kind == EnvironmentEntry.Kind.TILE and not entry.atlas_variants.is_empty():
		var tile_cells := _prepare_tile(candidate, entry)
		if tile_cells.is_empty(): _reject(candidate, "invalid_tile_resource"); return
		for tile_cell in tile_cells:
			if not footprint.has(tile_cell): footprint.append(tile_cell)
	if not _within_bounds(footprint, occupancy.bounds): _reject(candidate, "out_of_bounds"); return
	var blocked_mask := entry.blocked_occupancy_mask
	if entry.allow_road_clearance_overlap: blocked_mask &= ~WorldOccupancyMap.ROAD_CLEARANCE
	if occupancy.has_flags(footprint, blocked_mask): _reject(candidate, _occupancy_reason(footprint, occupancy, entry)); return
	var target := get_node_or_null(entry.target_path)
	if target == null or (entry.kind == EnvironmentEntry.Kind.SCENE and entry.scene == null) or (entry.kind == EnvironmentEntry.Kind.TILE and not target is TileMapLayer): _reject(candidate, "invalid_resource"); return
	if entry.kind == EnvironmentEntry.Kind.SCENE and not _scene_entry_is_node_2d(entry): _reject(candidate, "invalid_resource"); return
	var owner := _generated_id(chunk, entry.entry_id, cell)
	var claim := occupancy.claim_cells(footprint, entry.occupancy_flags | WorldOccupancyMap.NO_SPAWN, owner, PHASE)
	if not bool(claim.valid):
		_reject(candidate, String(claim.reason)); return
	_owned_claims.append(owner)
	if entry.kind == EnvironmentEntry.Kind.SCENE:
		var instance := entry.scene.instantiate() as Node2D
		if instance == null:
			occupancy.release_owner(owner)
			_owned_claims.erase(owner)
			_reject(candidate, "invalid_resource")
			return
		instance.position = _scene_position(cell, entry)
		candidate["position"] = instance.position
		instance.set_meta("generated_object_id", owner)
		instance.add_to_group(GENERATED_GROUP)
		EnvironmentContentInitializer.prepare(instance, owner, entry)
		target.add_child(instance)
		var content := EnvironmentContentInitializer.materialize(instance, _resolve_master_seed())
		if not content.errors.is_empty():
			for error in content.errors: _blocking(entry.entry_id, owner, "CONTENT_INITIALIZATION", String(error))
		if not content.manifests.is_empty(): candidate["content_manifests"] = content.manifests
	else:
		var layer := target as TileMapLayer
		if layer == null: occupancy.release_owner(owner); _owned_claims.erase(owner); _reject(candidate, "invalid_resource"); return
		var map_cell: Vector2i = candidate.get("map_cell", layer.local_to_map(Vector2(cell) * profile.logical_cell_size))
		layer.set_cell(map_cell, entry.source_id, candidate.get("atlas", entry.atlas_coords))
		_owned_tiles[owner] = {"layer":layer, "cell":map_cell}
	candidate.status = "ACCEPTED"; candidate.accepted = true; candidate.generated_id = owner; candidate.category = entry.category; candidate.footprint = footprint; accepted.append(candidate)
	var count_key := "%s/%d,%d" % [entry.entry_id, chunk.x, chunk.y]
	_accepted_counts[count_key] = int(_accepted_counts.get(count_key, 0)) + 1
	_accepted_world_counts[entry.entry_id] = int(_accepted_world_counts.get(entry.entry_id, 0)) + 1

func _scene_position(cell: Vector2i, entry: EnvironmentEntry) -> Vector2:
	var position := (Vector2(cell) + Vector2(0.5, 0.5)) * profile.logical_cell_size
	if entry.position_jitter_cells > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = WorldSeedService.derive_seed(_resolve_master_seed(), "environment/position/" + entry.entry_id, [cell.x, cell.y])
		position += Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * profile.logical_cell_size * entry.position_jitter_cells
	return position

func _footprint(cell: Vector2i, entry: EnvironmentEntry) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var padding := profile.clearance_cells + entry.minimum_spacing_cells
	for y in range(-padding, entry.footprint_size.y + padding):
		for x in range(-padding, entry.footprint_size.x + padding): cells.append(cell + entry.footprint_offset + Vector2i(x, y))
	return cells

func _prepare_tile(candidate: Dictionary, entry: EnvironmentEntry) -> Array[Vector2i]:
	var layer := get_node_or_null(entry.target_path) as TileMapLayer
	if layer == null or layer.tile_set == null or not layer.tile_set.has_source(entry.source_id): return []
	var source := layer.tile_set.get_source(entry.source_id) as TileSetAtlasSource
	if source == null: return []
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldSeedService.derive_seed(_resolve_master_seed(), "environment/tile/" + entry.entry_id, [candidate.cell.x, candidate.cell.y])
	var total := float(entry.atlas_variants.size())
	if not entry.atlas_variant_weights.is_empty():
		total = 0.0
		for weight in entry.atlas_variant_weights: total += weight
	var roll := rng.randf() * total
	var atlas: Vector2i = entry.atlas_variants.back()
	for index in range(entry.atlas_variants.size()):
		roll -= entry.atlas_variant_weights[index] if not entry.atlas_variant_weights.is_empty() else 1.0
		if roll < 0.0:
			atlas = entry.atlas_variants[index]
			break
	if not source.has_tile(atlas): return []
	var cell: Vector2i = candidate.cell
	var position := _scene_position(cell, entry)
	var map_cell := layer.local_to_map(layer.to_local(position))
	var data := source.get_tile_data(atlas, 0)
	var size := Vector2(source.get_tile_size_in_atlas(atlas) * source.texture_region_size)
	var local_rect := Rect2(layer.map_to_local(map_cell) - Vector2(data.texture_origin) - size * 0.5, size)
	var rect := layer.global_transform * local_rect
	var first := Vector2i((rect.position / profile.logical_cell_size).floor())
	var last := Vector2i(((rect.end - Vector2(0.001, 0.001)) / profile.logical_cell_size).floor())
	var cells: Array[Vector2i] = []
	var padding := profile.clearance_cells + entry.minimum_spacing_cells
	for y in range(first.y - padding, last.y + padding + 1):
		for x in range(first.x - padding, last.x + padding + 1): cells.append(Vector2i(x, y))
	candidate["atlas"] = atlas
	candidate["map_cell"] = map_cell
	return cells
func _entry_by_id(id: String) -> EnvironmentEntry:
	for entry in profile.entries:
		if entry != null and entry.entry_id == id: return entry
	return null
func _accepted_for_entry_in_chunk(entry_id: String, chunk: Vector2i) -> int:
	return int(_accepted_counts.get("%s/%d,%d" % [entry_id, chunk.x, chunk.y], 0))

func _build_forest(occupancy: WorldOccupancyMap, master_seed: int) -> void:
	_forest_cells.clear()
	_forest_land_cells = 0
	if not profile.forest_enabled: return
	var noise := FastNoiseLite.new()
	noise.seed = WorldSeedService.derive_seed(master_seed, "environment/forest", [])
	noise.frequency = 1.0 / profile.forest_patch_size_cells
	var ranked: Array[Dictionary] = []
	for y in range(occupancy.bounds.position.y, occupancy.bounds.end.y):
		for x in range(occupancy.bounds.position.x, occupancy.bounds.end.x):
			var cell := Vector2i(x, y)
			if occupancy.has_flags([cell], FOREST_FORBIDDEN): continue
			ranked.append({"cell": cell, "score": noise.get_noise_2d(x, y)})
	_forest_land_cells = ranked.size()
	ranked.sort_custom(func(a, b):
		if a.score != b.score: return a.score < b.score
		return a.cell.x < b.cell.x if a.cell.y == b.cell.y else a.cell.y < b.cell.y)
	for index in range(roundi(ranked.size() * profile.forest_coverage)):
		_forest_cells[ranked[index].cell] = true

func get_forest_statistics() -> Dictionary:
	return {"available_land_cells": _forest_land_cells, "forest_cells": _forest_cells.size(), "coverage": float(_forest_cells.size()) / maxi(1, _forest_land_cells)}
func _resolve_chunk_size_tiles() -> int:
	var source := get_node_or_null(world_seed_source_path)
	if source != null and source.has_method("get_debug_world_generation_info"):
		return maxi(1, int((source.call("get_debug_world_generation_info") as Dictionary).get("chunk_size_tiles", 16)))
	return 16
func _finite_chunks(bounds: Rect2i, chunk_size: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var first := Vector2i(floori(float(bounds.position.x) / chunk_size), floori(float(bounds.position.y) / chunk_size))
	var last_cell := bounds.end - Vector2i.ONE
	var last := Vector2i(floori(float(last_cell.x) / chunk_size), floori(float(last_cell.y) / chunk_size))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1): result.append(Vector2i(x, y))
	result.sort_custom(func(a, b): return a.x < b.x if a.y == b.y else a.y < b.y)
	return result
func _candidate_id(chunk: Vector2i, entry_id: String, cell: Vector2i) -> String:
	return "v3/environment/chunk:%d,%d/entry:%s/cell:%d,%d" % [chunk.x, chunk.y, entry_id, cell.x, cell.y]
func _generated_id(chunk: Vector2i, entry_id: String, cell: Vector2i) -> String:
	return _candidate_id(chunk, entry_id, cell)
func set_chunk_enumeration_reversed_for_test(value: bool) -> void:
	_reverse_chunk_enumeration_for_test = value
func _ranked_cell_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a.score) != int(b.score): return int(a.score) < int(b.score)
	var left := a.cell as Vector2i
	var right := b.cell as Vector2i
	return left.x < right.x if left.y == right.y else left.y < right.y
func _resolution_priority(entry: EnvironmentEntry, fallback: bool) -> int:
	var category := String(entry.category)
	if category == "structures": return -4 + (1 if fallback else 0)
	if category == "containers" or category == "pickups": return -2 + (1 if fallback else 0)
	if entry.kind == EnvironmentEntry.Kind.TILE and not entry.atlas_variants.is_empty(): return 0 + (1 if fallback else 0)
	var category_priority := 3
	if category == "trees": category_priority = 0
	elif category == "bushes" or category == "berry_bushes": category_priority = 1
	elif entry.kind == EnvironmentEntry.Kind.SCENE: category_priority = 2
	return 2 + category_priority * 2 + (1 if fallback else 0)
func _scene_is_node_2d(value: PackedScene) -> bool:
	if value == null: return false
	var probe := value.instantiate()
	var valid := probe is Node2D
	if probe != null: probe.free()
	return valid
func _scene_entry_is_node_2d(entry: EnvironmentEntry) -> bool:
	if _scene_entry_validity.has(entry.entry_id): return bool(_scene_entry_validity[entry.entry_id])
	var valid := _scene_is_node_2d(entry.scene)
	_scene_entry_validity[entry.entry_id] = valid
	return valid
func _resolve_master_seed() -> int:
	var source := get_node_or_null(world_seed_source_path)
	if source != null and source.has_method("get_debug_world_generation_info"):
		return int((source.call("get_debug_world_generation_info") as Dictionary).get("seed", 0))
	return 0
func _reject(candidate: Dictionary, reason: String) -> void:
	candidate.status = reason; rejections.append({"candidate_id":candidate.candidate_id, "entry_id":candidate.entry_id, "reason":reason})
func _clear_generated() -> void:
	var poi := get_node_or_null(poi_pass_path) as PoiPlacementPass
	if poi != null:
		for owner in _owned_claims: poi.occupancy.release_owner(owner)
	_owned_claims.clear()
	for item in _owned_tiles.values():
		var layer := (item as Dictionary).get("layer") as TileMapLayer
		if layer != null: layer.erase_cell((item as Dictionary).get("cell") as Vector2i)
	_owned_tiles.clear()
	for node in get_tree().get_nodes_in_group(GENERATED_GROUP):
		if node is Node:
			var generated := node as Node
			# Detach immediately so a synchronous repeated Generate cannot observe or
			# accumulate deferred-to-free instances from the previous run.
			if generated.get_parent() != null: generated.get_parent().remove_child(generated)
			generated.queue_free()
func get_generation_output_manifest() -> Dictionary:
	var placements := accepted.duplicate(true)
	placements.sort_custom(func(a, b): return String(a.generated_id) < String(b.generated_id))
	var rejects := rejections.duplicate(true)
	rejects.sort_custom(func(a, b): return String(a.candidate_id) < String(b.candidate_id))
	var rejection_counts := _canonical_rejection_counts(rejects)
	var chunk_counts := _canonical_chunk_counts(placements)
	var manifest := {"id":"environment_v3", "profile_id":profile.profile_id if profile != null else "", "chunk_size_tiles":_resolve_chunk_size_tiles(), "chunks":chunk_counts, "placements":placements, "rejections":rejects, "rejection_counts":rejection_counts}
	return {"id":"environment_v3", "environment_manifest":manifest, "environment_manifest_hash":GenerationHashes.sha256_of(manifest), "environment_content_hash":GenerationHashes.sha256_of(placements), "candidates":candidates, "accepted":placements, "rejections":rejects, "rejection_counts":rejection_counts, "chunk_counts":chunk_counts}
func _canonical_chunk_counts(placements: Array) -> Array[Dictionary]:
	var counts := {}
	for chunk in _finite_chunks_generated: counts["%d,%d" % [chunk.x, chunk.y]] = 0
	for placement in placements:
		var chunk := placement.chunk as Vector2i
		var key := "%d,%d" % [chunk.x, chunk.y]
		counts[key] = int(counts.get(key, 0)) + 1
	var keys: Array[String] = []
	for key in counts.keys(): keys.append(String(key))
	keys.sort()
	var result: Array[Dictionary] = []
	for key in keys: result.append({"chunk":key, "count":counts[key]})
	return result
func _canonical_rejection_counts(records: Array[Dictionary]) -> Array[Dictionary]:
	var counts := {}
	for record in records:
		var reason := String(record.reason)
		counts[reason] = int(counts.get(reason, 0)) + 1
	var reasons: Array[String] = []
	for reason in counts.keys(): reasons.append(String(reason))
	reasons.sort()
	var result: Array[Dictionary] = []
	for reason in reasons: result.append({"reason":reason, "count":counts[reason]})
	return result
func _within_bounds(cells: Array[Vector2i], bounds: Rect2i) -> bool:
	for cell in cells:
		if not bounds.has_point(cell): return false
	return true
func _occupancy_reason(cells: Array[Vector2i], occupancy: WorldOccupancyMap, entry: EnvironmentEntry) -> String:
	for pair in [[WorldOccupancyMap.ROAD,"road"],[WorldOccupancyMap.ROAD_CLEARANCE,"road_clearance"],[WorldOccupancyMap.WATER,"water"],[WorldOccupancyMap.POI,"poi"],[WorldOccupancyMap.BUILDING,"building"],[WorldOccupancyMap.NO_SPAWN,"environment_spacing"]]:
		if occupancy.has_flags(cells, int(pair[0])): return String(pair[1])
	return "occupancy_conflict"
func _blocking(entry: String, stable_id: String, reason: String, detail: String) -> void:
	var message := "EnvironmentGenerationPass blocking error stage=environment profile=%s entry=%s stable_id=%s seed=%d reason=%s detail=%s" % [profile.profile_id if profile != null else "<missing>", entry, stable_id, _resolve_master_seed(), reason, detail]
	blocking_errors.append(message); push_error(message)
