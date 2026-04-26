extends RefCounted
class_name WeaponNoiseController

const ENEMY_GROUP: StringName = &"enemy"

var controller
var hearing_radius_root: Node2D = null
var hearing_radius_line: Line2D = null
var current_hearing_radius: float = 140.0


func _init(owner) -> void:
	controller = owner
	if controller != null:
		current_hearing_radius = max(controller.hearing_base_radius, 1.0)


func update(delta: float) -> void:
	if controller == null or controller.player == null:
		return

	_update_hearing_radius(delta)
	if hearing_radius_root == null or hearing_radius_line == null:
		setup_hearing_radius_visual()
	update_hearing_radius_visual()


func emit_player_shot_noise() -> void:
	if controller == null or controller.player == null:
		return

	var stealth_noise_multiplier: float = get_player_noise_multiplier()
	var loudness_multiplier: float = _get_attachment_shot_loudness_multiplier()
	var shot_bonus_radius: float = max(controller.hearing_shot_bonus_radius, 0.0) * loudness_multiplier * stealth_noise_multiplier
	current_hearing_radius = max(
		current_hearing_radius,
		max(controller.hearing_base_radius, 1.0) * stealth_noise_multiplier + shot_bonus_radius
	)
	_sync_player_noise_level()
	_notify_enemies_about_noise(controller.player.global_position, current_hearing_radius)


func setup_hearing_radius_visual() -> void:
	if controller == null or controller.player == null:
		return

	hearing_radius_root = controller.player.get_node_or_null("HearingRadiusVisual") as Node2D
	if hearing_radius_root == null:
		hearing_radius_root = Node2D.new()
		hearing_radius_root.name = "HearingRadiusVisual"
		controller.player.call_deferred("add_child", hearing_radius_root)
		return

	hearing_radius_line = hearing_radius_root.get_node_or_null("Outline") as Line2D
	if hearing_radius_line == null:
		hearing_radius_line = Line2D.new()
		hearing_radius_line.name = "Outline"
		hearing_radius_root.call_deferred("add_child", hearing_radius_line)
		return

	hearing_radius_line.closed = true
	hearing_radius_line.antialiased = true
	hearing_radius_line.default_color = controller.hearing_radius_color
	hearing_radius_line.width = max(controller.hearing_radius_line_width, 0.5)


func update_hearing_radius_visual() -> void:
	if controller == null or controller.player == null:
		return
	if hearing_radius_root == null or hearing_radius_line == null:
		return

	hearing_radius_root.global_position = controller.player.global_position
	hearing_radius_root.visible = controller.show_hearing_radius
	if not controller.show_hearing_radius:
		return

	hearing_radius_line.default_color = controller.hearing_radius_color
	hearing_radius_line.width = max(controller.hearing_radius_line_width, 0.5)

	var radius: float = max(current_hearing_radius, 1.0)
	var segments: int = max(controller.hearing_radius_segments, 24)
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(segments):
		var t: float = float(i) / float(segments)
		var angle: float = TAU * t
		points.append(Vector2.RIGHT.rotated(angle) * radius)
	hearing_radius_line.points = points


func get_player_noise_multiplier() -> float:
	if controller == null or controller.player == null:
		return 1.0
	if controller.player.has_method("get_noise_loudness_multiplier"):
		return clamp(float(controller.player.call("get_noise_loudness_multiplier")), 0.05, 1.0)
	return 1.0


func sync_player_noise_level() -> void:
	_sync_player_noise_level()


func _update_hearing_radius(delta: float) -> void:
	var stealth_noise_multiplier: float = get_player_noise_multiplier()
	var base_radius: float = max(controller.hearing_base_radius, 1.0) * stealth_noise_multiplier
	var movement_bonus: float = controller.hearing_footstep_bonus_radius * stealth_noise_multiplier if controller._is_player_moving() else 0.0
	var target_radius: float = base_radius + max(movement_bonus, 0.0)
	current_hearing_radius = max(
		target_radius,
		move_toward(current_hearing_radius, target_radius, max(controller.hearing_decay_per_sec, 0.0) * delta)
	)
	_sync_player_noise_level()


func _get_attachment_shot_loudness_multiplier() -> float:
	if controller.current_weapon == null:
		return 1.0

	var attachments: Array[ItemData] = InventoryManager.get_attached_attachments(controller.current_weapon)
	if attachments.is_empty():
		return 1.0

	var final_multiplier: float = 1.0
	for attachment in attachments:
		if attachment == null:
			continue
		final_multiplier *= clamp(attachment.attachment_shot_loudness_multiplier, 0.1, 3.0)

	return clamp(final_multiplier, 0.05, 10.0)


func _notify_enemies_about_noise(noise_position: Vector2, noise_radius: float) -> void:
	for enemy_node in controller.get_tree().get_nodes_in_group(ENEMY_GROUP):
		if enemy_node == null or not is_instance_valid(enemy_node):
			continue
		if not enemy_node.has_method("on_player_noise_emitted"):
			continue
		enemy_node.call("on_player_noise_emitted", noise_position, noise_radius)


func _sync_player_noise_level() -> void:
	if controller == null or controller.player == null:
		return
	if controller.player.has_method("set_current_noise_level"):
		controller.player.call("set_current_noise_level", current_hearing_radius)
