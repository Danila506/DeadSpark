extends Node2D

const POPULATION_PROFILE = preload("res://Resources/WorldGen/EnemyPopulation/bandit_camp_population_profile.tres")
const PopulationPersistence = preload("res://World/Generation/enemy_population_persistence.gd")

@export var min_bandits_per_base: int = 2
@export var max_bandits_per_base: int = 4
@export var min_spawn_radius_px: float = 110.0
@export var max_spawn_radius_px: float = 220.0
@export var spawn_position_attempts: int = 16
@export var spawn_collision_radius_px: float = 14.0
@export var spawn_guards_deferred: bool = true
@export_range(1, 4, 1) var max_guards_spawned_per_frame: int = 1
@export_range(0.25, 8.0, 0.25) var guard_spawn_frame_budget_ms: float = 1.5
@export var bandit_scenes: Array[PackedScene] = [
	preload("res://Enemies/Bandits/Bandit_1/Bandit.tscn"),
	preload("res://Enemies/Bandits/Bandit_2/Bandit_2.tscn"),
	preload("res://Enemies/Bandits/Bandit_3/Bandit_3.tscn"),
	preload("res://Enemies/Bandits/Bandit_4/Bandit_4.tscn")
]
@export var world_generated_mode := false
@export var generated_object_id := ""
@export var population_profile: EnemyPopulationProfile = POPULATION_PROFILE

var _rng := RandomNumberGenerator.new()
var _pending_guard_jobs: Array[Dictionary] = []
var _guard_spawn_active: bool = false
var applied_population_manifest: EnemyPopulationManifest
var _population_states: Dictionary = {}


func _ready() -> void:
	if multiplayer.multiplayer_peer != null and not NetworkManager.is_server():
		set_process(false)
		return
	if world_generated_mode:
		if generated_object_id.strip_edges().is_empty():
			push_error("BanditBase: world-generated camp requires GeneratedObjectId")
		return
	_rng.seed = int(Time.get_ticks_usec()) ^ int(get_instance_id())
	if spawn_guards_deferred:
		_prepare_guard_spawn_jobs()
		if not _pending_guard_jobs.is_empty():
			_guard_spawn_active = true
			set_process(true)
			return
		return

	_spawn_guards_immediate()


func get_enemy_population_owner_id() -> String:
	return generated_object_id.strip_edges() if world_generated_mode else ""


func get_enemy_population_profile() -> EnemyPopulationProfile:
	return population_profile


func get_enemy_spawn_markers() -> Array:
	var records: Array[EnemySpawnMarkerRecord] = []
	for node in get_tree().get_nodes_in_group("enemy_population_marker"):
		if node is EnemySpawnMarker and is_ancestor_of(node):
			records.append((node as EnemySpawnMarker).to_population_record())
	records.sort_custom(func(a: EnemySpawnMarkerRecord, b: EnemySpawnMarkerRecord): return a.marker_id < b.marker_id)
	return records


func apply_enemy_population_manifest(manifest: EnemyPopulationManifest) -> Dictionary:
	if not world_generated_mode: return {"valid":false,"errors":["NOT_WORLD_GENERATED_CAMP"]}
	if manifest == null or manifest.owner_generated_object_id != get_enemy_population_owner_id() or population_profile == null or manifest.profile_id != population_profile.profile_id: return {"valid":false,"errors":["MANIFEST_OWNER_OR_PROFILE_MISMATCH"]}
	if applied_population_manifest != null:
		return {"valid":applied_population_manifest.manifest_hash()==manifest.manifest_hash(),"errors":[] if applied_population_manifest.manifest_hash()==manifest.manifest_hash() else ["CONFLICTING_POPULATION_MANIFEST"]}
	var markers := {}; for marker in get_enemy_spawn_markers(): markers[marker.marker_id]=true
	var ids := {}
	for record in manifest.records:
		if ids.has(record.population_id) or not markers.has(record.marker_id): return {"valid":false,"errors":["DUPLICATE_POPULATION_ID_OR_UNKNOWN_MARKER"]}
		ids[record.population_id]=true
		var scene := load(record.enemy_resource_key) as PackedScene
		if scene == null: return {"valid":false,"errors":["MISSING_ENEMY_SCENE"]}
		var actor := scene.instantiate() as Node2D
		if actor == null: return {"valid":false,"errors":["INVALID_ENEMY_SCENE"]}
		actor.position=to_local(record.position)
		actor.set_meta("population_id",record.population_id); actor.set_meta("population_owner_id",record.owner_generated_object_id); actor.set_meta("population_marker_id",record.marker_id); actor.set_meta("population_entry_id",record.enemy_entry_id); actor.set_meta("population_manifest_hash",manifest.manifest_hash()); actor.set_meta("population_state",record.initial_state); actor.add_to_group("camp_generated_population"); actor.add_to_group("generated_world_object"); actor.set_meta("world_generation_id",record.population_id); actor.set_meta("world_generation_scene_path",record.enemy_resource_key); actor.set_multiplayer_authority(1)
		_population_states[record.population_id]="alive"
		if actor.has_signal("died"): actor.died.connect(func(_enemy): mark_population_killed(record.population_id))
		add_child(actor)
	applied_population_manifest=manifest
	return {"valid":true,"errors":[]}


func clear_enemy_population() -> void:
	for child in get_children():
		if child.is_in_group("camp_generated_population"): child.queue_free()
	applied_population_manifest=null
	_population_states.clear()

func get_population_persistence_key()->String:return PopulationPersistence.get_persistence_key(get_enemy_population_owner_id())
func get_population_states()->Dictionary:return _population_states.duplicate(true)
func serialize_population_state()->Dictionary:return PopulationPersistence.serialize_camp(self)
func get_save_key() -> String:
	return PopulationPersistence.get_persistence_key(generated_object_id) if world_generated_mode else ""
func get_save_data() -> Dictionary:
	return serialize_population_state() if world_generated_mode and applied_population_manifest != null else {}
func apply_save_data(data: Dictionary) -> void:
	if not world_generated_mode or data.is_empty(): return
	var result := restore_population_state(data)
	if not result.valid: push_error("BanditBase restore failed: %s" % result.errors)
func restore_population_state(data:Dictionary)->Dictionary:return PopulationPersistence.restore_camp(self,data)
func mark_population_killed(population_id:String)->Dictionary:return _mark_population_state(population_id,"killed")
func mark_population_despawned(population_id:String)->Dictionary:return _mark_population_state(population_id,"despawned")
func _mark_population_state(population_id:String,state:String)->Dictionary:
	if applied_population_manifest==null or not _population_states.has(population_id):return {"valid":false,"errors":["UNKNOWN_POPULATION_ID"]}
	_population_states[population_id]=state
	if world_generated_mode: GameSaveManager.record_world_generation_object_state(self)
	if state=="despawned":
		for child in get_children():if child.get_meta("population_id","")==population_id:child.queue_free()
	return {"valid":true,"errors":[]}
func restore_persisted_population_state(manifest:EnemyPopulationManifest,states:Dictionary)->Dictionary:
	if applied_population_manifest!=null and applied_population_manifest.manifest_hash()!=manifest.manifest_hash():return {"valid":false,"errors":["INCOMPATIBLE_MATERIALIZED_POPULATION"]}
	if applied_population_manifest==null:
		var marker_ids := {}; for marker in get_enemy_spawn_markers(): marker_ids[marker.marker_id]=true
		for record in manifest.records:
			if not marker_ids.has(record.marker_id): return {"valid":false,"errors":["UNKNOWN_SAVED_MARKER"]}
		if population_profile!=null and population_profile.profile_id!=manifest.profile_id: push_warning("BanditBase: saved population manifest profile differs; saved state takes priority")
		for record in manifest.records:
			if String(states.get(record.population_id,"alive"))!="alive":continue
			var scene:=load(record.enemy_resource_key) as PackedScene;if scene==null:return {"valid":false,"errors":["MISSING_ENEMY_SCENE"]}
			var actor:=scene.instantiate() as Node2D;actor.position=to_local(record.position);actor.set_meta("population_id",record.population_id);actor.set_meta("population_owner_id",record.owner_generated_object_id);actor.set_meta("population_marker_id",record.marker_id);actor.set_meta("population_entry_id",record.enemy_entry_id);actor.set_meta("population_manifest_hash",manifest.manifest_hash());actor.set_meta("population_state","alive");actor.add_to_group("camp_generated_population");add_child(actor)
			if actor.has_signal("died"):actor.died.connect(func(_enemy):mark_population_killed(record.population_id))
		applied_population_manifest=manifest
	_population_states=states.duplicate(true)
	for child in get_children():
		var id := String(child.get_meta("population_id", ""))
		if not id.is_empty() and String(states.get(id, "alive")) != "alive":
			remove_child(child)
			child.queue_free()
	return {"valid":true,"errors":[]}


func _process(_delta: float) -> void:
	if not _guard_spawn_active:
		set_process(false)
		return

	var frame_start_usec := Time.get_ticks_usec()
	var frame_budget_usec := int(maxf(guard_spawn_frame_budget_ms, 0.25) * 1000.0)
	var spawn_budget := maxi(1, max_guards_spawned_per_frame)
	var spawned_this_frame := 0

	while spawned_this_frame < spawn_budget and not _pending_guard_jobs.is_empty():
		if Time.get_ticks_usec() - frame_start_usec >= frame_budget_usec:
			break
		_spawn_pending_guard(_pending_guard_jobs.pop_front())
		spawned_this_frame += 1

	if _pending_guard_jobs.is_empty():
		_guard_spawn_active = false
		set_process(false)


func _prepare_guard_spawn_jobs() -> void:
	_pending_guard_jobs.clear()

	var min_count := maxi(2, min_bandits_per_base)
	var max_count := maxi(min_count, max_bandits_per_base)
	var target_count := _rng.randi_range(min_count, max_count)

	for i in range(target_count):
		var spawn_scene := _pick_bandit_scene(i)
		if spawn_scene == null:
			continue
		var spawn_result := _find_guard_spawn_position(i)
		_pending_guard_jobs.append({
			"scene": spawn_scene,
			"position": spawn_result.get("position", global_position),
			"forced": false,
			"index_hint": i
		})

	while _pending_guard_jobs.size() < min_count:
		var forced_index := target_count + _pending_guard_jobs.size()
		var forced_scene := _pick_bandit_scene(forced_index)
		if forced_scene == null:
			break
		_pending_guard_jobs.append({
			"scene": forced_scene,
			"position": global_position + _fallback_guard_offset(forced_index),
			"forced": true,
			"index_hint": forced_index
		})


func _spawn_pending_guard(job: Dictionary) -> void:
	var spawn_scene := job.get("scene", null) as PackedScene
	if spawn_scene == null:
		return
	var bandit := spawn_scene.instantiate()
	if not (bandit is Node2D):
		if bandit != null:
			bandit.queue_free()
		return
	var bandit_node := bandit as Node2D
	add_child(bandit_node)
	bandit_node.global_position = job.get("position", global_position) as Vector2


func _spawn_guards_immediate() -> void:
	var min_count := maxi(2, min_bandits_per_base)
	var max_count := maxi(min_count, max_bandits_per_base)
	var target_count := _rng.randi_range(min_count, max_count)
	var spawned := 0

	for i in range(target_count):
		var spawn_scene := _pick_bandit_scene(i)
		if spawn_scene == null:
			continue
		var spawn_result := _find_guard_spawn_position(i)
		var spawn_pos := spawn_result.get("position", global_position) as Vector2
		var bandit := spawn_scene.instantiate()
		if not (bandit is Node2D):
			if bandit != null:
				bandit.queue_free()
			continue
		var bandit_node := bandit as Node2D
		add_child(bandit_node)
		bandit_node.global_position = spawn_pos
		spawned += 1

	while spawned < min_count:
		var forced_scene := _pick_bandit_scene(target_count + spawned)
		if forced_scene == null:
			break
		var forced_bandit := forced_scene.instantiate()
		if not (forced_bandit is Node2D):
			if forced_bandit != null:
				forced_bandit.queue_free()
			break
		var forced_bandit_node := forced_bandit as Node2D
		add_child(forced_bandit_node)
		forced_bandit_node.global_position = global_position + _fallback_guard_offset(target_count + spawned)
		spawned += 1


func _pick_bandit_scene(index_hint: int) -> PackedScene:
	if bandit_scenes.is_empty():
		return null
	var valid: Array[PackedScene] = []
	for scene in bandit_scenes:
		if scene != null:
			valid.append(scene)
	if valid.is_empty():
		return null
	var idx := int(posmod(index_hint + _rng.randi(), valid.size()))
	return valid[idx]


func _find_guard_spawn_position(index_hint: int) -> Dictionary:
	var query_count := 0
	for _i in range(maxi(1, spawn_position_attempts)):
		var angle := _rng.randf_range(0.0, TAU)
		var radius := _rng.randf_range(min_spawn_radius_px, maxf(min_spawn_radius_px, max_spawn_radius_px))
		var candidate := global_position + Vector2.RIGHT.rotated(angle) * radius
		query_count += 1
		if _is_spawn_position_free(candidate):
			return {
				"position": candidate,
				"queries": query_count
			}
	return {
		"position": global_position + _fallback_guard_offset(index_hint),
		"queries": query_count
	}


func _fallback_guard_offset(index_hint: int) -> Vector2:
	var ring_radius := maxf(min_spawn_radius_px, 96.0)
	var angle := (TAU / 6.0) * float(index_hint % 6)
	return Vector2.RIGHT.rotated(angle) * ring_radius


func _is_spawn_position_free(world_pos: Vector2) -> bool:
	var world := get_world_2d()
	if world == null:
		return true

	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = maxf(4.0, spawn_collision_radius_px)
	query.shape = shape
	query.transform = Transform2D(0.0, world_pos)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0x7fffffff
	var hits: Array = world.direct_space_state.intersect_shape(query, 8)
	return hits.is_empty()
