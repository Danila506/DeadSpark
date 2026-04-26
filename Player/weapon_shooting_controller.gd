extends RefCounted
class_name WeaponShootingController

const AKP_103_RESOURCE_PATH: String = "res://Resources/AR_Weapons/akp_103/akp_103.tres"
const AKP_103_SILENCED_SHOT_SOUND: AudioStream = preload("res://Assets/AudioWaw/WeaponSounds/akp_103/akp_103Silencer.wav")
const MIN_BULLET_DISTANCE: float = 8.0

var controller


func _init(owner) -> void:
	controller = owner


func update_shoot_cooldown(delta: float) -> void:
	if controller.shoot_cooldown > 0.0:
		controller.shoot_cooldown -= delta


func try_shoot() -> void:
	if controller.current_melee_weapon != null:
		return
	if not controller.is_aiming:
		return
	if controller.current_weapon == null:
		return
	if controller.is_reloading:
		return
	if controller.shoot_cooldown > 0.0:
		return
	if controller._get_ammo_in_mag() <= 0:
		return

	if should_fire_now():
		shoot()


func shoot() -> void:
	if controller.current_weapon == null:
		return

	var ammo_in_mag: int = controller._get_ammo_in_mag()
	if ammo_in_mag <= 0:
		return

	controller.shoot_cooldown = controller.current_weapon.fire_delay

	var muzzle: Marker2D = controller._get_current_muzzle()
	var spawn_pos: Vector2
	if muzzle != null:
		spawn_pos = muzzle.global_position
	else:
		spawn_pos = controller.player.global_position

	spawn_projectiles(spawn_pos)
	play_shot_sfx()

	var updated_ammo_in_mag: int = ammo_in_mag - 1
	var reserve_ammo: int = controller._get_reserve_ammo()
	controller._set_ammo_state(updated_ammo_in_mag, reserve_ammo)
	var active_weapon_slot: int = InventoryManager.get_active_weapon_slot()
	var weapon_broken: bool = InventoryManager.apply_endurance_percent_loss_to_equipped(
		active_weapon_slot,
		controller.current_weapon.weapon_endurance_loss_percent_per_shot
	)
	if weapon_broken:
		controller.is_reloading = false
		controller.reload_timer = 0.0
		controller.reload_uses_action_bar = false
		return
	emit_player_shot_noise()


func setup_shoot_sfx() -> void:
	var sounds_bus: StringName = &"Master"
	if AudioServer.get_bus_index(&"Sounds") != -1:
		sounds_bus = &"Sounds"

	if controller.weapon_shoot_sfx != null:
		controller.weapon_shoot_sfx.bus = sounds_bus
	if controller.weapon_reload_sfx != null:
		controller.weapon_reload_sfx.bus = sounds_bus


func play_shot_sfx() -> void:
	if controller.current_weapon == null:
		return
	if controller.weapon_shoot_sfx == null or not controller.weapon_shoot_sfx.is_inside_tree():
		return

	var shot_stream: AudioStream = resolve_shot_stream_for_current_weapon()
	if shot_stream == null:
		return

	controller.weapon_shoot_sfx.stream = shot_stream
	var loudness_multiplier: float = get_attachment_shot_loudness_multiplier()
	controller.weapon_shoot_sfx.volume_db = controller.current_weapon.shot_sound_volume_db + linear_to_db(max(loudness_multiplier, 0.001))
	if controller.weapon_shoot_sfx.playing:
		controller.weapon_shoot_sfx.stop()
	controller.weapon_shoot_sfx.play()


func resolve_shot_stream_for_current_weapon() -> AudioStream:
	if controller.current_weapon == null:
		return null

	if is_akp_103_with_silencer() and AKP_103_SILENCED_SHOT_SOUND != null:
		return AKP_103_SILENCED_SHOT_SOUND

	return controller.current_weapon.shot_sound


func is_akp_103_with_silencer() -> bool:
	if controller.current_weapon == null:
		return false

	var has_matching_name: bool = controller.current_weapon.item_name.strip_edges().to_lower() == "акп-103"
	var has_matching_resource: bool = controller.current_weapon.resource_path == AKP_103_RESOURCE_PATH
	if not has_matching_name and not has_matching_resource:
		return false

	return InventoryManager.get_attached_attachment(controller.current_weapon, ItemData.AttachmentSlot.SILENCER) != null


func emit_player_shot_noise() -> void:
	if controller.noise_controller != null:
		controller.noise_controller.emit_player_shot_noise()
		controller.current_hearing_radius = controller.noise_controller.current_hearing_radius


func get_attachment_shot_loudness_multiplier() -> float:
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


func should_fire_now() -> bool:
	if controller.current_weapon == null:
		return false

	if controller.current_weapon.pellets_per_shot > 1:
		return Input.is_action_just_pressed("shoot")

	return Input.is_action_pressed("shoot")


func spawn_projectiles(spawn_pos: Vector2) -> void:
	if controller.current_weapon == null:
		return

	var bullet_scene: PackedScene = controller.current_weapon.bullet_scene
	if bullet_scene == null:
		return

	var pellets: int = max(controller.current_weapon.pellets_per_shot, 1)
	for _i in range(pellets):
		var bullet: Node = bullet_scene.instantiate()
		controller.get_tree().current_scene.add_child(bullet)

		var shoot_dir: Vector2 = get_pellet_direction(controller._get_direction_to_aim_target(spawn_pos))
		var bullet_distance: float = get_pellet_distance()

		if bullet is Node2D:
			var bullet_2d: Node2D = bullet as Node2D
			bullet_2d.global_position = spawn_pos
			bullet_2d.rotation = shoot_dir.angle()

		var bullet_layer: int = 2
		var bullet_mask: int = 1
		if bullet is CollisionObject2D:
			var collision_object: CollisionObject2D = bullet as CollisionObject2D
			bullet_layer = collision_object.collision_layer
			bullet_mask = collision_object.collision_mask

		if bullet.has_method("initialize"):
			bullet.initialize(
				spawn_pos,
				shoot_dir,
				controller.current_weapon.bullet_speed,
				2.0,
				bullet_layer,
				bullet_mask,
				controller.current_weapon.damage,
				bullet_distance,
				controller.player
			)
		elif bullet.has_method("setup"):
			bullet.setup(shoot_dir, controller.current_weapon.damage, controller.current_weapon.bullet_speed)


func get_pellet_direction(base_direction: Vector2) -> Vector2:
	var direction: Vector2 = controller._get_spread_direction(base_direction)
	if controller.current_weapon == null or controller.current_weapon.pellets_per_shot <= 1:
		return direction

	var pellet_offset: float = deg_to_rad(randf_range(-controller.current_weapon.pellet_spread_degrees, controller.current_weapon.pellet_spread_degrees))
	return direction.rotated(pellet_offset).normalized()


func get_pellet_distance() -> float:
	if controller.current_weapon == null:
		return controller.current_bullet_distance

	var jitter_ratio: float = max(controller.current_weapon.pellet_distance_jitter_ratio, 0.0)
	if jitter_ratio <= 0.0:
		return controller.current_bullet_distance

	var distance_factor: float = randf_range(1.0 - jitter_ratio, 1.0)
	return max(MIN_BULLET_DISTANCE, controller.current_bullet_distance * distance_factor)
