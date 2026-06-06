extends Node2D

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

var _rng := RandomNumberGenerator.new()
var _pending_guard_jobs: Array[Dictionary] = []
var _guard_spawn_active: bool = false


func _ready() -> void:
	_rng.seed = int(Time.get_ticks_usec()) ^ int(get_instance_id())
	if spawn_guards_deferred:
		_prepare_guard_spawn_jobs()
		if not _pending_guard_jobs.is_empty():
			_guard_spawn_active = true
			set_process(true)
			return
		return

	_spawn_guards_immediate()


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
