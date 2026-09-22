extends "res://tests/forest_preview_capture.gd"

var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run_asset_tests")

func _check(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)

func _run_asset_tests() -> void:
	world_seed = 1337
	generate_full_world()
	_check(not _output.is_empty(), "missing generation output")
	_check(_environment.blocking_errors.is_empty(), "content initialization: %s" % str(_environment.blocking_errors))
	var variant_count := 0
	for entry in _environment.profile.entries:
		if entry.atlas_variants.is_empty(): continue
		var layer := _environment.get_node(entry.target_path) as TileMapLayer
		var source := layer.tile_set.get_source(entry.source_id) as TileSetAtlasSource
		for atlas in entry.atlas_variants:
			_check(source.has_tile(atlas), "missing authored tile %s %s" % [entry.entry_id, atlas])
			variant_count += 1
	_check(variant_count == 57, "expected 57 authored tile variants")
	var structures := {}
	var claimed := {}
	for placement in _environment.accepted:
		if placement.category == "structures": structures[placement.entry_id] = int(structures.get(placement.entry_id, 0)) + 1
		for cell in placement.footprint:
			_check(not claimed.has(cell), "overlap at %s" % cell)
			claimed[cell] = placement.generated_id
	_check(structures.size() == 5, "missing structure variants: %s" % structures)
	var guards := 0
	var containers := 0
	for node in get_tree().get_nodes_in_group(EnvironmentGenerationPass.GENERATED_GROUP):
		if node.has_method("get_loot_container_id"):
			if node.get("world_generated_loot") != null:
				containers += 1
				_check(node.get("_loot_manifest") != null, "container has no loot manifest")
			else:
				_check(node.get("applied_loot_manifest") != null, "building has no loot manifest")
		if not node.has_method("get_enemy_population_owner_id"): continue
		var manifest: EnemyPopulationManifest = node.get("applied_population_manifest")
		_check(manifest != null, "camp has no population manifest")
		if manifest == null: continue
		for actor in node.get_children():
			var id := String(actor.get_meta("population_id", ""))
			if id.is_empty(): continue
			guards += 1
			for record in manifest.records:
				if record.population_id == id:
					_check((actor as Node2D).global_position.is_equal_approx(record.position), "guard transformed twice")
		if not manifest.records.is_empty():
			var id := manifest.records[0].population_id
			node.call("mark_population_killed", id)
			var saved: Dictionary = node.call("get_save_data")
			node.call("apply_save_data", saved)
			for actor in node.get_children(): _check(String(actor.get_meta("population_id", "")) != id, "killed guard restored")
	_check(guards > 0, "no guards materialized")
	_check(containers > 0, "no standalone containers materialized")
	var disabled := _environment.profile.entries.back().duplicate(true) as EnvironmentEntry
	disabled.chunk_spawn_probability = 0.0
	_environment.candidates.clear()
	_environment._build_entry_chunk_candidates(BOUNDS, 1337, 16, Vector2i.ZERO, disabled)
	_check(_environment.candidates.is_empty(), "zero chunk probability did not disable spawning")
	print("ASSET_INTEGRATION variants=%d structures=%s guards=%d" % [variant_count, structures, guards])
	for failure in _failures: push_error(failure)
	print("ASSET_INTEGRATION_TEST=" + ("PASS" if _failures.is_empty() else "FAIL"))
	get_tree().quit(0 if _failures.is_empty() else 1)
