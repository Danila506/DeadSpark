extends Node2D

@export var min_bandits_per_base: int = 2
@export var max_bandits_per_base: int = 4
@export var min_spawn_radius_px: float = 110.0
@export var max_spawn_radius_px: float = 220.0
@export var spawn_position_attempts: int = 16
@export var spawn_collision_radius_px: float = 14.0
@export var bandit_scenes: Array[PackedScene] = [
	preload("res://Enemies/Bandits/Bandit_1/Bandit.tscn"),
	preload("res://Enemies/Bandits/Bandit_2/Bandit_2.tscn"),
	preload("res://Enemies/Bandits/Bandit_3/Bandit_3.tscn"),
	preload("res://Enemies/Bandits/Bandit_4/Bandit_4.tscn")
]

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = int(Time.get_ticks_usec()) ^ int(get_instance_id())
	_spawn_guards()


func _spawn_guards() -> void:
	var min_count := maxi(2, min_bandits_per_base)
	var max_count := maxi(min_count, max_bandits_per_base)
	var target_count := _rng.randi_range(min_count, max_count)
	var spawned := 0

	for i in range(target_count):
		var spawn_scene := _pick_bandit_scene(i)
		if spawn_scene == null:
			continue
		var spawn_pos := _find_guard_spawn_position(i)
		var bandit := spawn_scene.instantiate()
		if not (bandit is Node2D):
			if bandit != null:
				bandit.queue_free()
			continue
		var bandit_node := bandit as Node2D
		add_child(bandit_node)
		bandit_node.global_position = spawn_pos
		spawned += 1

	if spawned < min_count:
		_force_spawn_missing_guards(min_count - spawned, target_count)


func _force_spawn_missing_guards(missing_count: int, offset_seed: int) -> void:
	for i in range(missing_count):
		var spawn_scene := _pick_bandit_scene(offset_seed + i)
		if spawn_scene == null:
			continue
		var bandit := spawn_scene.instantiate()
		if not (bandit is Node2D):
			if bandit != null:
				bandit.queue_free()
			continue
		var forced_pos := global_position + _fallback_guard_offset(offset_seed + i)
		var bandit_node := bandit as Node2D
		add_child(bandit_node)
		bandit_node.global_position = forced_pos


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


func _find_guard_spawn_position(index_hint: int) -> Vector2:
	for _i in range(maxi(1, spawn_position_attempts)):
		var angle := _rng.randf_range(0.0, TAU)
		var radius := _rng.randf_range(min_spawn_radius_px, maxf(min_spawn_radius_px, max_spawn_radius_px))
		var candidate := global_position + Vector2.RIGHT.rotated(angle) * radius
		if _is_spawn_position_free(candidate):
			return candidate
	return global_position + _fallback_guard_offset(index_hint)


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
