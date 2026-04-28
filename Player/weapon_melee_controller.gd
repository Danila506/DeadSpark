extends RefCounted
class_name WeaponMeleeController

const ENEMY_GROUP: StringName = &"enemy"
const MELEE_SWING_ANIMATION_FRONT: String = "SwingAttackFront"
const MELEE_SWING_ANIMATION_BACK: String = "SwingAttackBack"
const MELEE_SWING_ANIMATION_RIGHT_LEGACY: String = "SwingAttackRight"
const MELEE_SWING_ANIMATION_DOWN_LEGACY: String = "SwingAttackDown"
const MELEE_COOLDOWN: float = 0.45

var controller


func _init(owner) -> void:
	controller = owner


func try_melee_attack() -> void:
	var manual_attack_pressed: bool = Input.is_action_just_pressed("shoot") or Input.is_action_just_pressed("melee_attack")
	if not controller.auto_melee_attack_enabled and not manual_attack_pressed:
		return

	var is_unarmed_attack: bool = can_use_unarmed_melee()
	if controller.current_melee_weapon == null and not is_unarmed_attack:
		return
	if controller.is_reloading:
		return
	if controller.melee_attack_cooldown > 0.0 or controller.melee_attack_timer > 0.0:
		return
	if find_best_melee_target() == null:
		return

	controller.melee_attack_cooldown = MELEE_COOLDOWN
	controller.melee_attack_timer = max(controller.melee_attack_duration_sec, 0.05)
	controller.melee_hit_timer = max(controller.melee_hit_delay_sec, 0.01)
	controller.melee_hit_applied = false
	controller.melee_attack_animation_playing = false
	play_melee_attack_animation()


func update_melee_attack(delta: float) -> void:
	if controller.melee_attack_cooldown > 0.0:
		controller.melee_attack_cooldown -= delta

	if controller.melee_attack_timer <= 0.0:
		return

	controller.melee_attack_timer -= delta
	controller.melee_hit_timer -= delta

	if not controller.melee_hit_applied and controller.melee_hit_timer <= 0.0:
		apply_melee_hit()
		controller.melee_hit_applied = true

	if controller.melee_attack_timer <= 0.0:
		controller.melee_attack_timer = 0.0
		controller.melee_hit_timer = 0.0
		controller.melee_hit_applied = false
		stop_melee_attack_animation()


func play_melee_attack_animation() -> void:
	var melee_slot: EquipmentVisualSlot = get_melee_visual_slot()
	if melee_slot == null or melee_slot.sprite_frames == null:
		return
	if not melee_slot.visible:
		return

	var attack_direction: String = get_melee_attack_direction()
	var animation_name: String = ""
	match attack_direction:
		"down", "up":
			if melee_slot.sprite_frames.has_animation(MELEE_SWING_ANIMATION_BACK):
				animation_name = MELEE_SWING_ANIMATION_BACK
			elif melee_slot.sprite_frames.has_animation(MELEE_SWING_ANIMATION_DOWN_LEGACY):
				animation_name = MELEE_SWING_ANIMATION_DOWN_LEGACY
			elif melee_slot.sprite_frames.has_animation(MELEE_SWING_ANIMATION_FRONT):
				animation_name = MELEE_SWING_ANIMATION_FRONT
			elif melee_slot.sprite_frames.has_animation(MELEE_SWING_ANIMATION_RIGHT_LEGACY):
				animation_name = MELEE_SWING_ANIMATION_RIGHT_LEGACY
		_:
			if melee_slot.sprite_frames.has_animation(MELEE_SWING_ANIMATION_FRONT):
				animation_name = MELEE_SWING_ANIMATION_FRONT
			elif melee_slot.sprite_frames.has_animation(MELEE_SWING_ANIMATION_RIGHT_LEGACY):
				animation_name = MELEE_SWING_ANIMATION_RIGHT_LEGACY
			elif melee_slot.sprite_frames.has_animation(MELEE_SWING_ANIMATION_BACK):
				animation_name = MELEE_SWING_ANIMATION_BACK
			elif melee_slot.sprite_frames.has_animation(MELEE_SWING_ANIMATION_DOWN_LEGACY):
				animation_name = MELEE_SWING_ANIMATION_DOWN_LEGACY

	if animation_name == "":
		return

	melee_slot.play(animation_name)
	melee_slot.flip_h = attack_direction == "left"
	melee_slot.flip_v = attack_direction == "up"
	melee_slot.speed_scale = max(controller.melee_attack_anim_speed_scale, 0.05)
	controller.melee_attack_animation_playing = true


func stop_melee_attack_animation() -> void:
	if not controller.melee_attack_animation_playing:
		return

	controller.melee_attack_animation_playing = false
	var melee_slot: EquipmentVisualSlot = get_melee_visual_slot()
	if melee_slot != null:
		melee_slot.flip_h = false
		melee_slot.flip_v = false
	if controller.player != null and controller.player.has_method("_force_refresh_animation"):
		controller.player.call("_force_refresh_animation")


func get_melee_visual_slot() -> EquipmentVisualSlot:
	for child in controller.player.get_children():
		if child is EquipmentVisualSlot:
			var slot: EquipmentVisualSlot = child as EquipmentVisualSlot
			if slot.item_type == ItemData.ItemType.MeleeWeapon:
				return slot
	return null


func apply_melee_hit() -> void:
	var best_target: Node2D = find_best_melee_target()
	if best_target == null:
		return

	var melee_damage: float = max(controller.unarmed_melee_damage, 0.0)
	if controller.current_melee_weapon != null:
		melee_damage = max(controller.current_melee_weapon.damage, melee_damage)

	var hit_context: Dictionary = {
		"source_position": controller.player.global_position,
		"hit_position": best_target.global_position,
		"hitbox_type": "body",
		"damage_zone": "body"
	}
	best_target.call("take_damage_from", melee_damage, controller.player, hit_context)
	if controller.current_melee_weapon != null:
		InventoryManager.apply_endurance_percent_loss_to_equipped(
			ItemData.ItemType.MeleeWeapon,
			controller.current_melee_weapon.weapon_endurance_loss_percent_per_melee_hit
		)
	start_melee_camera_shake()


func can_use_unarmed_melee() -> bool:
	return controller.current_weapon == null and controller.current_melee_weapon == null


func find_best_melee_target() -> Node2D:
	if controller.player == null:
		return null

	var attack_direction: Vector2 = get_player_facing_vector()
	var full_circle_attack: bool = controller.melee_hit_angle_degrees >= 360.0
	var half_angle_cos: float = cos(deg_to_rad(clamp(controller.melee_hit_angle_degrees, 1.0, 359.0) * 0.5))
	var best_target: Node2D = null
	var best_distance: float = INF
	for enemy_node in controller.get_tree().get_nodes_in_group(ENEMY_GROUP):
		if enemy_node == null or not is_instance_valid(enemy_node):
			continue
		if is_damage_target_dead(enemy_node):
			continue
		if not (enemy_node is Node2D):
			continue
		if not enemy_node.has_method("take_damage_from"):
			continue

		var enemy: Node2D = enemy_node as Node2D
		var to_enemy: Vector2 = enemy.global_position - controller.player.global_position
		var distance: float = to_enemy.length()
		if distance > max(controller.melee_attack_range, 1.0):
			continue

		if not full_circle_attack:
			var direction: Vector2 = to_enemy.normalized()
			if direction.dot(attack_direction) < half_angle_cos:
				continue

		if distance < best_distance:
			best_distance = distance
			best_target = enemy

	return best_target


func is_damage_target_dead(target: Node) -> bool:
	if target == null:
		return true
	if target.has_method("is_dead"):
		var dead_result: Variant = target.call("is_dead")
		return typeof(dead_result) == TYPE_BOOL and dead_result
	if "is_dead" in target:
		var field_value: Variant = target.get("is_dead")
		return typeof(field_value) == TYPE_BOOL and field_value
	return false


func start_melee_camera_shake() -> void:
	if controller.player_camera == null:
		return
	controller.melee_camera_shake_time_left = max(controller.melee_camera_shake_duration_sec, 0.01)


func update_melee_camera_shake(delta: float) -> void:
	if controller.player_camera == null:
		return

	if controller.melee_camera_shake_time_left <= 0.0:
		if controller.player_camera.offset != Vector2.ZERO:
			controller.player_camera.offset = Vector2.ZERO
		return

	controller.melee_camera_shake_time_left = max(controller.melee_camera_shake_time_left - delta, 0.0)
	var t: float = controller.melee_camera_shake_time_left / max(controller.melee_camera_shake_duration_sec, 0.01)
	var amplitude: float = max(controller.melee_camera_shake_strength, 0.0) * t
	controller.player_camera.offset = Vector2(
		randf_range(-amplitude, amplitude),
		randf_range(-amplitude, amplitude)
	)


func spawn_melee_blood_effect(hit_world_position: Vector2) -> void:
	var blood_frames: SpriteFrames = get_melee_blood_frames()
	if blood_frames == null:
		return
	var animation_name: String = resolve_blood_hit_animation_name(blood_frames)
	if animation_name == "":
		return

	var fx_root: Node = controller.get_tree().current_scene
	if fx_root == null:
		fx_root = controller.player
	if fx_root == null:
		return

	var blood_sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	blood_sprite.sprite_frames = blood_frames
	blood_sprite.animation = animation_name
	blood_sprite.speed_scale = 1.0
	blood_sprite.scale = controller.melee_blood_effect_scale
	blood_sprite.global_position = hit_world_position + controller.melee_blood_offset
	if controller.melee_blood_random_rotation:
		blood_sprite.rotation = randf_range(-0.45, 0.45)
	blood_sprite.z_index = 20
	blood_sprite.top_level = true

	fx_root.add_child(blood_sprite)
	blood_sprite.play(animation_name)
	blood_sprite.animation_finished.connect(func() -> void:
		if is_instance_valid(blood_sprite):
			blood_sprite.queue_free()
	)


func get_melee_blood_frames() -> SpriteFrames:
	return controller.melee_blood_sprite_frames


func resolve_blood_animation_name(frames: SpriteFrames) -> String:
	if frames == null:
		return ""

	if not controller.melee_blood_animation_name.is_empty() and frames.has_animation(controller.melee_blood_animation_name):
		frames.set_animation_loop(controller.melee_blood_animation_name, false)
		frames.set_animation_speed(controller.melee_blood_animation_name, max(controller.melee_blood_anim_fps, 1.0))
		return controller.melee_blood_animation_name

	var names: PackedStringArray = frames.get_animation_names()
	if names.is_empty():
		return ""

	var fallback_name: String = String(names[0])
	frames.set_animation_loop(fallback_name, false)
	frames.set_animation_speed(fallback_name, max(controller.melee_blood_anim_fps, 1.0))
	return fallback_name


func resolve_blood_hit_animation_name(frames: SpriteFrames) -> String:
	if frames == null:
		return ""

	var candidates: Array[String] = []
	for name in controller.melee_blood_hit_animation_names:
		var trimmed_name: String = String(name).strip_edges()
		if trimmed_name.is_empty():
			continue
		if frames.has_animation(trimmed_name):
			candidates.append(trimmed_name)

	if not candidates.is_empty():
		var random_name: String = candidates[randi() % candidates.size()]
		frames.set_animation_loop(random_name, false)
		frames.set_animation_speed(random_name, max(controller.melee_blood_anim_fps, 1.0))
		return random_name

	return resolve_blood_animation_name(frames)


func get_melee_attack_direction() -> String:
	if controller.player != null and "facing_direction" in controller.player:
		return String(controller.player.facing_direction)
	return "right"


func get_player_facing_vector() -> Vector2:
	match get_melee_attack_direction():
		"up":
			return Vector2.UP
		"down":
			return Vector2.DOWN
		"left":
			return Vector2.LEFT
		_:
			return Vector2.RIGHT
