extends RefCounted
class_name ShellEjectionEffect

const SHELLS_TEXTURE: Texture2D = preload("res://Assets/Effects/shells.png")
const REGULAR_SHELL_REGIONS: Array[Rect2] = [
	Rect2(7, 6, 5, 6),
	Rect2(12, 7, 5, 6)
]
const SHOTGUN_SHELL_REGIONS: Array[Rect2] = [
	Rect2(22, 7, 5, 6),
	Rect2(28, 8, 5, 6)
]
const SHELL_SCALE: Vector2 = Vector2(2.0, 2.0)
const EJECT_DURATION_SEC: float = 0.34
const REST_LIFETIME_SEC: float = 18.0
const FADE_OUT_SEC: float = 1.2
const SHELL_ROOT_NAME: StringName = &"GroundShells"
const SHELL_ROOT_Z_INDEX: int = -1
const SHELL_Z_INDEX: int = 0


static func spawn(
	tree: SceneTree,
	origin: Vector2,
	shot_direction: Vector2,
	is_shotgun_shell: bool = false,
	eject_side: float = 1.0
) -> void:
	if tree == null or SHELLS_TEXTURE == null:
		return

	var root: Node = tree.current_scene
	if root == null:
		return
	var shell_root: Node2D = _get_or_create_shell_root(root)
	if shell_root == null:
		return

	var shell := Sprite2D.new()
	shell.name = "ShellEjection"
	shell.texture = SHELLS_TEXTURE
	shell.region_enabled = true
	shell.region_rect = _get_shell_region(is_shotgun_shell)
	shell.centered = true
	shell.scale = SHELL_SCALE
	shell.z_index = SHELL_Z_INDEX
	shell.rotation = randf_range(-PI, PI)
	shell_root.add_child(shell)
	shell.global_position = origin

	var direction := shot_direction.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var side_direction := Vector2(-direction.y, direction.x) * (1.0 if eject_side >= 0.0 else -1.0)
	var eject_distance: float = randf_range(10.0, 18.0) if is_shotgun_shell else randf_range(12.0, 24.0)
	var backward_distance: float = randf_range(2.0, 7.0)
	var target_position: Vector2 = origin + side_direction * eject_distance - direction * backward_distance
	target_position += Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))

	var tween: Tween = shell.create_tween()
	tween.set_parallel(true)
	tween.tween_property(shell, "global_position", target_position, EJECT_DURATION_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(shell, "rotation", shell.rotation + randf_range(2.0, 5.5) * (1.0 if randf() >= 0.5 else -1.0), EJECT_DURATION_SEC)
	tween.tween_property(shell, "scale", SHELL_SCALE * randf_range(0.82, 0.96), EJECT_DURATION_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_interval(REST_LIFETIME_SEC)
	tween.tween_property(shell, "modulate:a", 0.0, FADE_OUT_SEC)
	tween.finished.connect(func() -> void:
		if is_instance_valid(shell):
			shell.queue_free()
	)


static func _get_shell_region(is_shotgun_shell: bool) -> Rect2:
	var regions: Array[Rect2] = SHOTGUN_SHELL_REGIONS if is_shotgun_shell else REGULAR_SHELL_REGIONS
	return regions[randi() % regions.size()]


static func _get_or_create_shell_root(scene_root: Node) -> Node2D:
	var shell_root: Node2D = scene_root.get_node_or_null(NodePath(String(SHELL_ROOT_NAME))) as Node2D
	if shell_root == null:
		shell_root = Node2D.new()
		shell_root.name = SHELL_ROOT_NAME
		shell_root.z_as_relative = false
		shell_root.z_index = SHELL_ROOT_Z_INDEX
		scene_root.add_child(shell_root)
	else:
		shell_root.z_as_relative = false
		shell_root.z_index = SHELL_ROOT_Z_INDEX

	_place_shell_root_below_world_objects(scene_root, shell_root)
	return shell_root


static func _place_shell_root_below_world_objects(scene_root: Node, shell_root: Node2D) -> void:
	var y_sort_root: Node = scene_root.get_node_or_null("Y-Sort_Objects")
	if y_sort_root == null:
		return

	var y_sort_index: int = y_sort_root.get_index()
	if shell_root.get_index() != y_sort_index - 1:
		scene_root.move_child(shell_root, y_sort_index)
