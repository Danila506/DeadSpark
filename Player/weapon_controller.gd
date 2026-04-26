extends Node
class_name WeaponController

@export var default_cursor: Texture2D = preload("res://cur.png")

@onready var player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var anim: AnimatedSprite2D = $"../BodySprite"
@onready var inventory_root: Control = $"../../../UI/InventoryRoot"

@onready var muzzle_up: Marker2D = $"../Muzzles/MuzzleUp"
@onready var muzzle_down: Marker2D = $"../Muzzles/MuzzleDown"
@onready var muzzle_left: Marker2D = $"../Muzzles/MuzzleLeft"
@onready var muzzle_right: Marker2D = $"../Muzzles/MuzzleRight"
@onready var weapon_shoot_sfx: AudioStreamPlayer = null
@onready var weapon_reload_sfx: AudioStreamPlayer = null
@onready var player_camera: Camera2D = $"../Camera2D"

@export var melee_attack_anim_speed_scale: float = 1.0
@export var melee_attack_duration_sec: float = 0.55
@export var melee_hit_delay_sec: float = 0.22
@export var melee_attack_range: float = 30.0
@export var melee_hit_angle_degrees: float = 800.0
@export var unarmed_melee_damage: float = 8.0
@export var auto_melee_attack_enabled: bool = true
@export var melee_camera_shake_strength: float = 3.0
@export var melee_camera_shake_duration_sec: float = 0.10
@export var melee_blood_sprite_frames: SpriteFrames = null
@export var melee_blood_animation_name: String = "hit"
@export var melee_blood_hit_animation_names: Array[String] = ["bloodyVariant1", "BloodyVariant2"]
@export var melee_blood_anim_fps: float = 16.0
@export var melee_blood_effect_scale: Vector2 = Vector2(0.8, 0.8)
@export var melee_blood_random_rotation: bool = true
@export var melee_blood_offset: Vector2 = Vector2(0.0, -8.0)
@export var show_melee_debug_sector: bool = false
@export var melee_debug_color: Color = Color(1.0, 0.2, 0.2, 0.85)
@export_range(6, 64, 1) var melee_debug_segments: int = 20
@export var cursor_speed_min_px_per_sec: float = 120.0
@export var cursor_speed_max_px_per_sec: float = 1400.0
@export var aim_target_offset: Vector2 = Vector2(0.0, 0.0)
@export var hearing_base_radius: float = 140.0
@export var hearing_footstep_bonus_radius: float = 80.0
@export var hearing_shot_bonus_radius: float = 240.0
@export var hearing_decay_per_sec: float = 180.0
@export var show_hearing_radius: bool = true
@export var hearing_radius_color: Color = Color(1.0, 0.95, 0.35, 0.45)
@export var hearing_radius_line_width: float = 1.2
@export_range(24, 128, 1) var hearing_radius_segments: int = 64

var current_weapon: ItemData = null
var current_melee_weapon: ItemData = null
var is_aiming: bool = false
var shoot_cooldown: float = 0.0
var current_spread_degrees: float = 0.0
var current_bullet_distance: float = 0.0
var is_reloading: bool = false
var reload_timer: float = 0.0
var reload_uses_action_bar: bool = false
var cursor_heat_ratio: float = 0.0
var aim_settle_ratio: float = 1.0
var melee_attack_cooldown: float = 0.0
var melee_attack_timer: float = 0.0
var melee_hit_timer: float = 0.0
var melee_hit_applied: bool = false
var melee_attack_animation_playing: bool = false
var previous_mouse_position: Vector2 = Vector2.ZERO
var cursor_motion_ratio: float = 0.0
var aim_visual_ratio: float = 1.0
var current_hearing_radius: float = 140.0
var melee_debug_root: Node2D = null
var melee_debug_fill: Polygon2D = null
var melee_debug_outline: Line2D = null
var hearing_radius_root: Node2D = null
var hearing_radius_line: Line2D = null
var melee_camera_shake_time_left: float = 0.0
var noise_controller
var reload_controller
var shooting_controller
var melee_controller

const CURSOR_HEAT_BUILD_PER_SEC: float = 0.75
const CURSOR_HEAT_RECOVER_PER_SEC: float = 1.25
const AIM_SETTLE_RECOVER_PER_SEC: float = 1.85
const MIN_BULLET_DISTANCE: float = 8.0
const WEAPON_NOISE_CONTROLLER = preload("res://Player/weapon_noise_controller.gd")
const WEAPON_RELOAD_CONTROLLER = preload("res://Player/weapon_reload_controller.gd")
const WEAPON_SHOOTING_CONTROLLER = preload("res://Player/weapon_shooting_controller.gd")
const WEAPON_MELEE_CONTROLLER = preload("res://Player/weapon_melee_controller.gd")


func _ready() -> void:
	noise_controller = WEAPON_NOISE_CONTROLLER.new(self)
	reload_controller = WEAPON_RELOAD_CONTROLLER.new(self)
	shooting_controller = WEAPON_SHOOTING_CONTROLLER.new(self)
	melee_controller = WEAPON_MELEE_CONTROLLER.new(self)
	_ensure_reload_input_action()
	current_hearing_radius = max(hearing_base_radius, 1.0)
	_resolve_weapon_audio_nodes()
	_setup_shoot_sfx()
	if noise_controller != null:
		Callable(noise_controller, "setup_hearing_radius_visual").call_deferred()
	_setup_melee_debug_visual.call_deferred()


func _process(delta: float) -> void:
	_update_current_weapon()
	if noise_controller != null:
		noise_controller.update(delta)
	if melee_debug_root == null or melee_debug_fill == null or melee_debug_outline == null:
		_setup_melee_debug_visual()
	_update_melee_debug_visual()
	_update_aim_state()
	_update_cursor_motion_ratio(delta)
	_update_spread(delta)
	_update_cursor_heat(delta)
	_update_cursor()
	if shooting_controller != null:
		shooting_controller.update_shoot_cooldown(delta)
	if melee_controller != null:
		melee_controller.update_melee_attack(delta)
		melee_controller.update_melee_camera_shake(delta)
	if reload_controller != null:
		reload_controller.update(delta)
	_sync_reload_state_from_controller()
	if reload_controller != null:
		reload_controller.try_reload()
	_sync_reload_state_from_controller()
	if melee_controller != null:
		melee_controller.try_melee_attack()
	if shooting_controller != null:
		shooting_controller.try_shoot()


func _update_current_weapon() -> void:
	var previous_weapon: ItemData = current_weapon
	var previous_melee_weapon: ItemData = current_melee_weapon
	var active_weapon_slot: int = InventoryManager.get_active_weapon_slot()
	current_weapon = null
	current_melee_weapon = null

	if active_weapon_slot in [ItemData.ItemType.AR_Weapon, ItemData.ItemType.Pistols]:
		current_weapon = InventoryManager.get_equipped(active_weapon_slot)
	elif active_weapon_slot == ItemData.ItemType.MeleeWeapon:
		current_melee_weapon = InventoryManager.get_equipped(active_weapon_slot)

	if previous_weapon != current_weapon or previous_melee_weapon != current_melee_weapon:
		_cancel_reload()
		_stop_weapon_audio()
		current_spread_degrees = 0.0
		current_bullet_distance = 0.0
		cursor_heat_ratio = 0.0
		aim_settle_ratio = 1.0
		melee_attack_cooldown = 0.0
		melee_attack_timer = 0.0
		melee_hit_timer = 0.0
		melee_hit_applied = false
		melee_attack_animation_playing = false
		cursor_motion_ratio = 0.0
		aim_visual_ratio = 1.0
		previous_mouse_position = Vector2.ZERO


func _stop_weapon_audio() -> void:
	var audio_root: Node = get_node_or_null("../Audio")
	if audio_root != null:
		for child in audio_root.get_children():
			if not (child is AudioStreamPlayer):
				continue

			var stream_player: AudioStreamPlayer = child as AudioStreamPlayer
			if stream_player.name == "SnowWalk":
				continue
			if stream_player.playing:
				stream_player.stop()
		return

	# Fallback for old scene layouts without Audio root.
	if weapon_shoot_sfx != null and weapon_shoot_sfx.playing:
		weapon_shoot_sfx.stop()
	if weapon_reload_sfx != null and weapon_reload_sfx.playing:
		weapon_reload_sfx.stop()


func _update_aim_state() -> void:
	var was_aiming: bool = is_aiming
	var inventory_open: bool = inventory_root != null and "is_inventory_open" in inventory_root and inventory_root.is_inventory_open
	is_aiming = not inventory_open and current_weapon != null and Input.is_action_pressed("aim")
	if is_aiming and not was_aiming:
		_reset_aim_settle()
	if not is_aiming and was_aiming:
		cursor_heat_ratio = 0.0
		cursor_motion_ratio = 0.0
		aim_visual_ratio = 1.0


func _update_cursor() -> void:
	if is_reloading:
		Input.set_custom_mouse_cursor(null)
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		return

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if is_aiming and current_weapon != null:
		var cursor_texture: Texture2D = _get_current_aim_cursor()
		if cursor_texture != null:
			var hotspot: Vector2 = cursor_texture.get_size() / 2.0
			Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_ARROW, hotspot)
			return

	if default_cursor != null:
		var default_hotspot: Vector2 = default_cursor.get_size() / 2.0
		Input.set_custom_mouse_cursor(default_cursor, Input.CURSOR_ARROW, default_hotspot)
	else:
		Input.set_custom_mouse_cursor(null)


func _update_spread(delta: float) -> void:
	if current_weapon == null:
		current_spread_degrees = 0.0
		current_bullet_distance = 0.0
		aim_settle_ratio = 1.0
		aim_visual_ratio = 1.0
		return

	if not is_aiming or is_reloading:
		aim_settle_ratio = 1.0
	else:
		aim_settle_ratio = move_toward(aim_settle_ratio, 0.0, _get_spread_settle_speed() * delta)

	var hold_ratio: float = _get_hold_spread_ratio()
	var settle_ratio: float = aim_settle_ratio
	var motion_ratio: float = _get_cursor_motion_ratio()
	var effective_ratio: float = max(max(hold_ratio, settle_ratio), motion_ratio)
	var running_bonus_multiplier: float = current_weapon.running_spread_multiplier if _is_player_moving() else 1.0

	current_spread_degrees = lerpf(
		current_weapon.min_spread_degrees,
		current_weapon.max_spread_degrees,
		effective_ratio
	)
	current_spread_degrees *= max(running_bonus_multiplier, 1.0)
	current_spread_degrees *= _get_scope_spread_multiplier()
	var spread_min: float = current_weapon.min_spread_degrees
	var spread_max: float = max(current_weapon.max_spread_degrees, spread_min + 0.001)
	aim_visual_ratio = clamp(inverse_lerp(spread_min, spread_max, current_spread_degrees), 0.0, 1.0)
	current_bullet_distance = max(MIN_BULLET_DISTANCE, min(_get_aim_distance(), current_weapon.bullet_max_distance))


func _setup_shoot_sfx() -> void:
	if shooting_controller != null:
		shooting_controller.setup_shoot_sfx()


func _resolve_weapon_audio_nodes() -> void:
	if player == null:
		return

	var audio_root: Node = get_node_or_null("../Audio")
	if audio_root == null:
		audio_root = Node.new()
		audio_root.name = "Audio"
		player.add_child(audio_root)

	weapon_shoot_sfx = audio_root.get_node_or_null("WeaponShoot") as AudioStreamPlayer
	if weapon_shoot_sfx == null:
		weapon_shoot_sfx = AudioStreamPlayer.new()
		weapon_shoot_sfx.name = "WeaponShoot"
		audio_root.add_child(weapon_shoot_sfx)

	weapon_reload_sfx = audio_root.get_node_or_null("WeaponReload") as AudioStreamPlayer
	if weapon_reload_sfx == null:
		weapon_reload_sfx = AudioStreamPlayer.new()
		weapon_reload_sfx.name = "WeaponReload"
		audio_root.add_child(weapon_reload_sfx)


func _notify_enemies_about_noise(noise_position: Vector2, noise_radius: float) -> void:
	if noise_controller == null:
		return
	noise_controller._notify_enemies_about_noise(noise_position, noise_radius)


func _update_hearing_radius(delta: float) -> void:
	if noise_controller != null:
		noise_controller.update(delta)
		current_hearing_radius = noise_controller.current_hearing_radius


func _get_player_noise_multiplier() -> float:
	if noise_controller != null:
		return noise_controller.get_player_noise_multiplier()
	return 1.0


func _sync_player_noise_level() -> void:
	if noise_controller != null:
		noise_controller.sync_player_noise_level()


func _setup_hearing_radius_visual() -> void:
	if noise_controller != null:
		noise_controller.setup_hearing_radius_visual()
		hearing_radius_root = noise_controller.hearing_radius_root
		hearing_radius_line = noise_controller.hearing_radius_line


func _update_hearing_radius_visual() -> void:
	if noise_controller != null:
		noise_controller.update_hearing_radius_visual()
		current_hearing_radius = noise_controller.current_hearing_radius


func get_aim_direction_4way() -> String:
	return _get_mouse_direction_4way()


func is_in_aim_mode() -> bool:
	return is_aiming


func has_weapon_equipped() -> bool:
	return current_weapon != null


func get_weapon_body_frames() -> SpriteFrames:
	if current_weapon == null:
		return null

	return current_weapon.body_sprite_frames


func get_ammo_in_mag() -> int:
	return _get_ammo_in_mag()


func get_reserve_ammo() -> int:
	return _get_reserve_ammo()


func get_is_reloading() -> bool:
	return is_reloading


func is_melee_attack_anim_active() -> bool:
	return melee_attack_timer > 0.0


func _get_mouse_world_direction() -> Vector2:
	var dir: Vector2 = _get_direction_to_aim_target(player.global_position)

	if dir == Vector2.ZERO:
		return Vector2.DOWN

	return dir


func _get_mouse_direction_4way() -> String:
	var dir: Vector2 = _get_mouse_world_direction()

	if abs(dir.x) > abs(dir.y):
		if dir.x > 0.0:
			return "right"
		else:
			return "left"
	else:
		if dir.y > 0.0:
			return "down"
		else:
			return "up"


func _get_current_muzzle() -> Marker2D:
	match _get_mouse_direction_4way():
		"up":
			return muzzle_up
		"down":
			return muzzle_down
		"left":
			return muzzle_left
		"right":
			return muzzle_right
		_:
			return muzzle_down


func _get_spread_direction(base_direction: Vector2) -> Vector2:
	if current_weapon == null:
		return base_direction

	if current_spread_degrees <= 0.0:
		return base_direction

	var spread_offset: float = deg_to_rad(randf_range(-current_spread_degrees, current_spread_degrees))
	return base_direction.rotated(spread_offset).normalized()


func _get_current_aim_cursor() -> Texture2D:
	if current_weapon == null:
		return null

	var color_ratio: float = aim_visual_ratio

	if _is_player_moving() and current_weapon.aim_cursor_high_spread != null:
		return current_weapon.aim_cursor_high_spread

	if color_ratio >= 0.75 and current_weapon.aim_cursor_high_spread != null:
		return current_weapon.aim_cursor_high_spread

	if color_ratio >= 0.5 and current_weapon.aim_cursor_medium_spread != null:
		return current_weapon.aim_cursor_medium_spread

	if color_ratio >= 0.25 and current_weapon.aim_cursor_low_spread != null:
		return current_weapon.aim_cursor_low_spread

	return current_weapon.aim_cursor


func _update_cursor_heat(delta: float) -> void:
	var settle_speed: float = _get_spread_settle_speed()

	if current_weapon == null or not is_aiming:
		cursor_heat_ratio = move_toward(cursor_heat_ratio, 0.0, settle_speed * delta)
		return

	if _is_player_moving():
		cursor_heat_ratio = 1.0
		return

	if Input.is_action_pressed("shoot") and not is_reloading and _get_ammo_in_mag() > 0:
		cursor_heat_ratio = move_toward(cursor_heat_ratio, 1.0, CURSOR_HEAT_BUILD_PER_SEC * delta)
	else:
		cursor_heat_ratio = move_toward(cursor_heat_ratio, 0.0, settle_speed * delta)


func _get_spread_settle_speed() -> float:
	if current_weapon == null:
		return AIM_SETTLE_RECOVER_PER_SEC

	var weapon_ratio: float = clamp(current_weapon.spread_recovery_per_sec / 7.0, 0.2, 2.0)
	var base_speed: float = AIM_SETTLE_RECOVER_PER_SEC * weapon_ratio
	var settle_time_multiplier: float = _get_scope_aim_settle_time_multiplier()
	return base_speed / max(settle_time_multiplier, 0.01)


func _get_cursor_heat_recovery_speed() -> float:
	if current_weapon == null:
		return CURSOR_HEAT_RECOVER_PER_SEC

	var weapon_ratio: float = clamp(current_weapon.spread_recovery_per_sec / 7.0, 0.2, 2.0)
	return CURSOR_HEAT_RECOVER_PER_SEC * weapon_ratio


func _get_scope_aim_settle_time_multiplier() -> float:
	if current_weapon == null:
		return 1.0

	var attachments: Array[ItemData] = InventoryManager.get_attached_attachments(current_weapon)
	if attachments.is_empty():
		return 1.0

	var final_multiplier: float = 1.0
	for attachment in attachments:
		if attachment == null:
			continue
		final_multiplier *= clamp(attachment.attachment_aim_settle_time_multiplier, 0.1, 3.0)
		if attachment.is_scope_attachment or attachment.attachment_slot == ItemData.AttachmentSlot.SCOPE:
			final_multiplier *= clamp(attachment.scope_aim_settle_time_multiplier, 0.1, 3.0)

	return clamp(final_multiplier, 0.05, 10.0)


func _get_scope_spread_multiplier() -> float:
	if current_weapon == null:
		return 1.0

	var attachments: Array[ItemData] = InventoryManager.get_attached_attachments(current_weapon)
	if attachments.is_empty():
		return 1.0

	var final_multiplier: float = 1.0
	for attachment in attachments:
		if attachment == null:
			continue
		final_multiplier *= clamp(attachment.attachment_spread_multiplier, 0.1, 3.0)
		if attachment.is_scope_attachment or attachment.attachment_slot == ItemData.AttachmentSlot.SCOPE:
			final_multiplier *= clamp(attachment.scope_spread_multiplier, 0.1, 3.0)

	return clamp(final_multiplier, 0.05, 10.0)


func _get_hold_spread_ratio() -> float:
	return cursor_heat_ratio


func _update_cursor_motion_ratio(delta: float) -> void:
	var mouse_world_pos: Vector2 = player.get_global_mouse_position()
	if previous_mouse_position == Vector2.ZERO:
		previous_mouse_position = mouse_world_pos
		return

	var distance_moved: float = mouse_world_pos.distance_to(previous_mouse_position)
	previous_mouse_position = mouse_world_pos

	if delta <= 0.0:
		return

	var speed_px_per_sec: float = distance_moved / delta
	var target_ratio: float = clamp(
		inverse_lerp(cursor_speed_min_px_per_sec, cursor_speed_max_px_per_sec, speed_px_per_sec),
		0.0,
		1.0
	)

	if not is_aiming or is_reloading or current_weapon == null:
		target_ratio = 0.0

	cursor_motion_ratio = move_toward(cursor_motion_ratio, target_ratio, _get_spread_settle_speed() * delta)


func _get_cursor_motion_ratio() -> float:
	return cursor_motion_ratio


func _get_aim_distance() -> float:
	return player.global_position.distance_to(_get_aim_target_world_position())


func _is_player_moving() -> bool:
	return player.velocity.length() > 0.1


func _get_aim_target_world_position() -> Vector2:
	return player.get_global_mouse_position() + aim_target_offset


func _get_direction_to_aim_target(from_position: Vector2) -> Vector2:
	var direction: Vector2 = (_get_aim_target_world_position() - from_position).normalized()
	if direction == Vector2.ZERO:
		return Vector2.DOWN
	return direction


func _start_reload() -> void:
	if reload_controller != null:
		reload_controller.start_reload()
	_sync_reload_state_from_controller()


func _play_reload_sfx() -> void:
	if reload_controller != null:
		reload_controller.play_reload_sfx()


func _cancel_reload() -> void:
	if reload_controller != null:
		reload_controller.cancel_reload()
	_sync_reload_state_from_controller()


func _finish_reload() -> void:
	if reload_controller != null:
		reload_controller.finish_reload()
	_sync_reload_state_from_controller()


func _sync_reload_state_from_controller() -> void:
	if reload_controller == null:
		return
	is_reloading = reload_controller.is_reloading
	reload_timer = reload_controller.reload_timer
	reload_uses_action_bar = reload_controller.reload_uses_action_bar


func _get_ammo_in_mag() -> int:
	if current_weapon == null:
		return 0

	return InventoryManager.get_ammo_in_mag(current_weapon)


func _get_reserve_ammo() -> int:
	if current_weapon == null:
		return 0

	return InventoryManager.get_reserve_ammo(current_weapon)


func _set_ammo_state(ammo_in_mag: int, reserve_ammo: int) -> void:
	if current_weapon == null:
		return

	InventoryManager.set_ammo_state(current_weapon, ammo_in_mag, reserve_ammo)


func _reset_aim_settle() -> void:
	aim_settle_ratio = 1.0


func _ensure_reload_input_action() -> void:
	if not InputMap.has_action("reload"):
		InputMap.add_action("reload")

	for event in InputMap.action_get_events("reload"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_R:
			return

	var reload_key := InputEventKey.new()
	reload_key.physical_keycode = KEY_R
	InputMap.action_add_event("reload", reload_key)


func _setup_melee_debug_visual() -> void:
	if player == null:
		return

	melee_debug_root = player.get_node_or_null("MeleeDebugSector") as Node2D
	if melee_debug_root == null:
		melee_debug_root = Node2D.new()
		melee_debug_root.name = "MeleeDebugSector"
		player.call_deferred("add_child", melee_debug_root)
		return

	melee_debug_fill = melee_debug_root.get_node_or_null("Fill") as Polygon2D
	if melee_debug_fill == null:
		melee_debug_fill = Polygon2D.new()
		melee_debug_fill.name = "Fill"
		melee_debug_root.call_deferred("add_child", melee_debug_fill)
		return

	melee_debug_outline = melee_debug_root.get_node_or_null("Outline") as Line2D
	if melee_debug_outline == null:
		melee_debug_outline = Line2D.new()
		melee_debug_outline.name = "Outline"
		melee_debug_root.call_deferred("add_child", melee_debug_outline)
		return

	melee_debug_outline.width = 2.0
	melee_debug_outline.default_color = melee_debug_color
	melee_debug_fill.color = Color(melee_debug_color.r, melee_debug_color.g, melee_debug_color.b, 0.18)
	melee_debug_root.visible = false


func _update_melee_debug_visual() -> void:
	if melee_debug_root == null or melee_debug_fill == null or melee_debug_outline == null:
		return

	var should_show: bool = show_melee_debug_sector and current_melee_weapon != null and player != null
	melee_debug_root.visible = should_show
	if not should_show:
		return

	melee_debug_root.global_position = player.global_position
	melee_debug_outline.default_color = melee_debug_color
	melee_debug_fill.color = Color(melee_debug_color.r, melee_debug_color.g, melee_debug_color.b, 0.18)

	var sector_range: float = max(melee_attack_range, 1.0)
	if melee_hit_angle_degrees >= 360.0:
		var circle_points: PackedVector2Array = PackedVector2Array()
		var circle_segments: int = max(melee_debug_segments, 16)
		for i in range(circle_segments + 1):
			var t: float = float(i) / float(circle_segments)
			var angle: float = TAU * t
			circle_points.append(Vector2.RIGHT.rotated(angle) * sector_range)
		melee_debug_fill.polygon = circle_points

		var circle_outline_points: PackedVector2Array = circle_points.duplicate()
		if circle_outline_points.size() > 0:
			circle_outline_points.append(circle_outline_points[0])
		melee_debug_outline.points = circle_outline_points
		return

	var half_angle: float = deg_to_rad(clamp(melee_hit_angle_degrees, 1.0, 359.0) * 0.5)
	var facing_vector: Vector2 = Vector2.RIGHT
	if melee_controller != null:
		facing_vector = melee_controller.get_player_facing_vector()
	var base_angle: float = facing_vector.angle()
	var segments: int = max(melee_debug_segments, 6)

	var polygon_points: PackedVector2Array = PackedVector2Array()
	polygon_points.append(Vector2.ZERO)
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var angle: float = lerpf(base_angle - half_angle, base_angle + half_angle, t)
		var point: Vector2 = Vector2.RIGHT.rotated(angle) * sector_range
		polygon_points.append(point)
	melee_debug_fill.polygon = polygon_points

	var outline_points: PackedVector2Array = PackedVector2Array()
	outline_points.append(Vector2.ZERO)
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var angle: float = lerpf(base_angle - half_angle, base_angle + half_angle, t)
		var point: Vector2 = Vector2.RIGHT.rotated(angle) * sector_range
		outline_points.append(point)
	outline_points.append(Vector2.ZERO)
	melee_debug_outline.points = outline_points
