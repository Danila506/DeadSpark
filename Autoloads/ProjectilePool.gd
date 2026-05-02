extends Node

const META_POOL_KEY: StringName = &"projectile_pool_key"

@export var max_pooled_per_scene: int = 96

var _pool: Dictionary = {}


func acquire_projectile(scene: PackedScene, parent: Node) -> Node:
	if scene == null or parent == null:
		return null

	var key: String = _get_scene_key(scene)
	var bucket: Array = _pool.get(key, [])
	while not bucket.is_empty():
		var projectile: Node = bucket.pop_back()
		if not is_instance_valid(projectile):
			continue
		_pool[key] = bucket
		projectile.set_meta(META_POOL_KEY, key)
		if projectile.get_parent() != null:
			projectile.get_parent().remove_child(projectile)
		parent.add_child(projectile)
		if projectile.has_method("reset_for_pool_reuse"):
			projectile.call("reset_for_pool_reuse")
		return projectile

	var new_projectile: Node = scene.instantiate()
	if new_projectile != null:
		new_projectile.set_meta(META_POOL_KEY, key)
		parent.add_child(new_projectile)
	return new_projectile


func release_projectile(projectile: Node) -> void:
	if projectile == null or not is_instance_valid(projectile):
		return
	if not projectile.has_meta(META_POOL_KEY):
		projectile.queue_free()
		return

	var key: String = String(projectile.get_meta(META_POOL_KEY))
	var bucket: Array = _pool.get(key, [])
	if bucket.size() >= max(max_pooled_per_scene, 0):
		projectile.queue_free()
		return

	if projectile.has_method("prepare_for_pool"):
		projectile.call("prepare_for_pool")
	if projectile.get_parent() != null:
		projectile.get_parent().remove_child(projectile)
	add_child(projectile)
	bucket.append(projectile)
	_pool[key] = bucket


func _get_scene_key(scene: PackedScene) -> String:
	if not scene.resource_path.is_empty():
		return scene.resource_path
	return str(scene.get_instance_id())
