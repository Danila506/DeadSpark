extends RefCounted
class_name PlayerMovementController

var player


func _init(owner) -> void:
	player = owner


func movement_loop(delta: float, inventory_root, weapon_controller) -> void:
	if player == null:
		return

	if player.action_in_progress and player.action_blocks_movement:
		player.velocity = Vector2.ZERO
		player._update_walk_snow_sfx(Vector2.ZERO, delta)
		if not player._play_action_animation_if_available():
			player.idle()
		player.move_and_slide()
		return

	if inventory_root != null and inventory_root.is_inventory_open:
		player.velocity = Vector2.ZERO
		player._update_walk_snow_sfx(Vector2.ZERO, delta)
		player.idle()
		player.move_and_slide()
		return

	var input_vector: Vector2 = Input.get_vector("left", "right", "up", "down")
	player.velocity = input_vector * player.base_move_speed * player._get_current_speed_multiplier()

	if weapon_controller != null and weapon_controller.is_in_aim_mode() and weapon_controller.has_weapon_equipped():
		player._update_aim_movement_animation(input_vector)
	else:
		if input_vector == Vector2.ZERO:
			player.idle()
		else:
			player.update_move_animation(input_vector)

	player._apply_current_animation_speed(input_vector == Vector2.ZERO)
	player._update_walk_snow_sfx(input_vector, delta)
	player.move_and_slide()


func update_stealth_state(action_name: StringName, base_noise_level: float, stealth_noise_multiplier: float) -> Dictionary:
	var is_stealth: bool = Input.is_action_pressed(action_name)
	var noise_multiplier: float = clamp(stealth_noise_multiplier, 0.05, 1.0) if is_stealth else 1.0
	return {
		"is_stealth": is_stealth,
		"current_noise_level": base_noise_level * noise_multiplier
	}
