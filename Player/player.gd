extends CharacterBody2D

signal stats_changed
signal status_effects_changed

@export var max_health: float = 100.0
@export var max_water: float = 100.0
@export var max_food: float = 100.0
@export var max_stamina: float = 100.0

var health: float = 100.0
var water: float = 100.0
var food: float = 100.0
var stamina: float = 100.0
var radiation: float = 0.0
var is_bleeding: bool = false
var is_fractured: bool = false
var is_diseased: bool = false

@export var water_drain_amount: float = 8.0
@export var water_drain_interval: float = 6.0
var water_timer: float = 0.0

@export var food_drain_amount: float = 1.0
@export var food_drain_interval: float = 3.5
var food_timer: float = 0.0
@export var passive_regen_per_sec: float = 1.2
@export var passive_regen_threshold_ratio: float = 0.75
@export var bleeding_damage_amount: float = 2.0
@export var bleeding_damage_interval: float = 1.0
@export_range(0.0, 1.0, 0.01) var bleeding_auto_heal_chance: float = 0.10
var bleeding_timer: float = 0.0
@export var disease_damage_amount: float = 0.8
@export var disease_damage_interval: float = 1.3
@export var disease_duration_sec: float = 22.0
var disease_tick_timer: float = 0.0
var disease_time_left: float = 0.0

@export var stamina_drain_per_sec: float = 1.0
@export var stamina_recovery_per_sec: float = 3.0
@export var min_exhausted_speed_multiplier: float = 0.45
@export var min_exhausted_animation_multiplier: float = 0.55
@export_range(0.0, 1.0, 0.01) var fracture_speed_multiplier: float = 0.5
@export_range(0.0, 1.0, 0.01) var fracture_from_bandit_chance: float = 0.05
@export var incoming_bullet_source_groups: Array[StringName] = [&"bandit"]
@export var incoming_bite_source_groups: Array[StringName] = [&"wolf"]
@export var incoming_melee_source_groups: Array[StringName] = [&"enemy"]
@export var incoming_explosion_source_groups: Array[StringName] = []
@export var incoming_default_damage_type: int = ItemData.DamageType.GENERIC

var is_dead: bool = false
var facing_direction: String = "down"

enum {
	DOWN,
	UP,
	LEFT,
	RIGHT
}

@export var speed: float = 100.0
@export var base_move_speed: float = 100.0
@export var stealth_action_name: StringName = &"stealth"
@export_range(0.05, 1.0, 0.05) var stealth_speed_multiplier: float = 0.5
@export var base_animation_speed_scale: float = 1.0
@export_range(0.05, 1.0, 0.05) var stealth_animation_multiplier: float = 0.5
@export var base_noise_level: float = 1.0
@export_range(0.05, 1.0, 0.05) var stealth_noise_multiplier: float = 0.25

const WALK_SNOW_STREAM: AudioStream = preload("res://Assets/AudioWaw/WeaponSounds/WalkSnow.wav")
const WALK_SNOW_MIN_MOVE_LENGTH: float = 0.1
const WALK_SNOW_MIN_PLAY_SECONDS: float = 0.3


@onready var anim: AnimatedSprite2D = $BodySprite
@onready var camera_2d: Camera2D = $Camera2D
@onready var inventory_root = $"../../UI/InventoryRoot"
@onready var weapon_controller: WeaponController = $WeaponController
@onready var action_bar_root: Control = $ActionBarRoot
@onready var action_bar_fill: TextureProgressBar = $ActionBarRoot/ActionBarFill
@onready var walk_snow_sfx: AudioStreamPlayer = null

var idle_dir: int = DOWN
var equipment_visual_slots: Array[EquipmentVisualSlot] = []
var action_in_progress: bool = false
var action_blocks_movement: bool = true
var action_duration: float = 0.0
var action_elapsed: float = 0.0
var action_complete_callback: Callable = Callable()
var current_action_animation: String = ""
var status_hint_label: Label = null
var status_hint_queue: Array[Dictionary] = []
var status_hint_time_left: float = 0.0
var status_hint_total_duration: float = 3.0
var status_hint_base_position: Vector2 = Vector2(-20.0, -20.0)
var low_water_hint_timer: float = 0.0
var low_food_hint_timer: float = 0.0
var was_low_water: bool = false
var was_low_food: bool = false
var walk_snow_min_play_time_left: float = 0.0
var death_overlay_layer: CanvasLayer = null
var death_overlay_rect: ColorRect = null
var death_overlay_label: Label = null
var bleeding_trail_timer: float = 0.0
var is_stealth: bool = false
var current_noise_level: float = 1.0

@export var bleeding_effect_animation_name: String = "Bleeding"
@export var bleeding_trail_interval_sec: float = 0.20
@export var bleeding_trail_lifetime_sec: float = 1.2
@export var bleeding_trail_scale: Vector2 = Vector2(0.95, 0.95)
@export var bleeding_trail_offset: Vector2 = Vector2(0.0, 2.0)
@export var bleeding_trail_random_radius: float = 2.0
@export var bleeding_trail_random_rotation: bool = true
@export var bleeding_trail_z_index: int = 1
@export var hit_blood_animation_names: Array[String] = ["bloodyVariant1", "BloodyVariant2"]
@export var hit_blood_anim_fps: float = 16.0
@export var hit_blood_effect_scale: Vector2 = Vector2(0.9, 0.9)
@export var hit_blood_offset: Vector2 = Vector2(0.0, -10.0)
@export var hit_blood_fly_distance: float = 14.0
@export var hit_blood_fly_duration_sec: float = 0.16
@export var hit_blood_z_index: int = 35

const LOW_NEED_HINT_THRESHOLD_RATIO: float = 0.5
const LOW_NEED_HINT_INTERVAL_SEC: float = 30.0
const LOW_WATER_HINT_TEXT: String = "Я хочу пить"
const LOW_FOOD_HINT_TEXT: String = "Я хочу есть"
const LOW_WATER_HINT_COLOR: Color = Color(0.45, 0.8, 1.0, 1.0)
const LOW_FOOD_HINT_COLOR: Color = Color(0.9, 0.8, 0.62, 1.0)
const PLAYER_VITALS_CONTROLLER = preload("res://Player/player_vitals_controller.gd")
const PLAYER_INTERACTION_CONTROLLER = preload("res://Player/player_interaction_controller.gd")
const PLAYER_MOVEMENT_CONTROLLER = preload("res://Player/player_movement_controller.gd")
const PLAYER_TIMED_ACTION_CONTROLLER = preload("res://Player/player_timed_action_controller.gd")
const PLAYER_STATUS_HINT_CONTROLLER = preload("res://Player/player_status_hint_controller.gd")
const PLAYER_DEATH_EFFECTS_CONTROLLER = preload("res://Player/player_death_effects_controller.gd")
const PLAYER_BLOOD_EFFECTS_CONTROLLER = preload("res://Player/player_blood_effects_controller.gd")

var vitals_controller
var interaction_controller
var movement_controller
var timed_action_controller
var status_hint_controller
var death_effects_controller
var blood_effects_controller


func _ready() -> void:
	vitals_controller = PLAYER_VITALS_CONTROLLER.new(self)
	interaction_controller = PLAYER_INTERACTION_CONTROLLER.new(self)
	movement_controller = PLAYER_MOVEMENT_CONTROLLER.new(self)
	timed_action_controller = PLAYER_TIMED_ACTION_CONTROLLER.new(self)
	status_hint_controller = PLAYER_STATUS_HINT_CONTROLLER.new(self)
	death_effects_controller = PLAYER_DEATH_EFFECTS_CONTROLLER.new(self)
	blood_effects_controller = PLAYER_BLOOD_EFFECTS_CONTROLLER.new(self)
	add_to_group("player")
	base_move_speed = max(max(base_move_speed, speed), 1.0)
	speed = base_move_speed
	_update_stealth_state()
	walk_snow_sfx = _resolve_walk_snow_sfx()
	_setup_walk_snow_sfx()
	stats_changed.emit()
	_collect_equipment_visual_slots()
	_connect_inventory_signals()
	_refresh_equipment_visuals()
	_force_refresh_animation()
	_hide_action_bar()
	_ensure_status_hint_label()
	if GameSaveManager != null and GameSaveManager.has_method("register_persistent_node"):
		GameSaveManager.register_persistent_node(self)


func _resolve_walk_snow_sfx() -> AudioStreamPlayer:
	var from_audio_node: AudioStreamPlayer = get_node_or_null("Audio/SnowWalk") as AudioStreamPlayer
	if from_audio_node != null:
		return from_audio_node
	return get_node_or_null("SnowWalk") as AudioStreamPlayer


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		call_deferred("_go_to_menu")
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey

		if key_event.physical_keycode == KEY_E:
			if inventory_root != null and "is_inventory_open" in inventory_root and inventory_root.is_inventory_open:
				get_viewport().set_input_as_handled()
				return
			if _trigger_primary_interaction():
				get_viewport().set_input_as_handled()
				return
			if inventory_root != null and inventory_root.has_method("pickup_first_nearby_item"):
				if inventory_root.pickup_first_nearby_item():
					get_viewport().set_input_as_handled()
					return

		if key_event.physical_keycode == KEY_F:
			if _trigger_secondary_interaction():
				get_viewport().set_input_as_handled()
				return

		if key_event.physical_keycode == KEY_F5:
			if GameSaveManager != null and GameSaveManager.has_method("save_game"):
				GameSaveManager.save_game()
			get_viewport().set_input_as_handled()
			return

		if key_event.physical_keycode == KEY_F9:
			if GameSaveManager != null and GameSaveManager.has_method("load_game"):
				GameSaveManager.load_game()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton

		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			InventoryManager.cycle_active_weapon(1)
			_refresh_equipment_visuals()
			_force_refresh_animation()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			InventoryManager.cycle_active_weapon(-1)
			_refresh_equipment_visuals()
			_force_refresh_animation()


func _physics_process(_delta: float) -> void:
	if is_dead:
		return

	_update_stealth_state()
	movement_loop(_delta)


func _process(delta: float) -> void:
	if is_dead:
		return

	_update_needs(delta)
	_update_stamina(delta)
	_update_timed_action(delta)
	_update_low_need_hints(delta)
	_update_status_hint_visual(delta)
	_update_bleeding_trail(delta)


func _update_needs(delta: float) -> void:
	if vitals_controller != null:
		vitals_controller.update_needs(delta)


func _update_stamina(delta: float) -> void:
	if vitals_controller != null:
		vitals_controller.update_stamina(delta, inventory_root)


func _collect_equipment_visual_slots() -> void:
	equipment_visual_slots.clear()
	_find_equipment_visual_slots_recursive(self)


func _find_equipment_visual_slots_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is EquipmentVisualSlot:
			equipment_visual_slots.append(child)

		_find_equipment_visual_slots_recursive(child)


func _connect_inventory_signals() -> void:
	if not InventoryManager.equipment_changed.is_connected(_on_equipment_changed):
		InventoryManager.equipment_changed.connect(_on_equipment_changed)


func _on_equipment_changed(_slot_type: int, _item: ItemData) -> void:
	_refresh_equipment_visuals()
	_force_refresh_animation()


func _refresh_equipment_visuals() -> void:
	var active_weapon_slot: int = InventoryManager.get_active_weapon_slot()

	for visual_slot in equipment_visual_slots:
		var equipped_item: ItemData = InventoryManager.get_equipped(visual_slot.item_type)

		if equipped_item == null or equipped_item.equipped_frames == null:
			visual_slot.sprite_frames = null
			visual_slot.visible = false
			continue

		if _is_switchable_weapon_slot(visual_slot.item_type) and visual_slot.item_type != active_weapon_slot:
			visual_slot.sprite_frames = equipped_item.equipped_frames
			visual_slot.visible = false
			continue

		visual_slot.sprite_frames = equipped_item.equipped_frames
		visual_slot.visible = true

		_apply_equipment_animation(visual_slot, String(anim.animation))


func _sync_equipment_animation(animation_name: String) -> void:
	var active_weapon_slot: int = InventoryManager.get_active_weapon_slot()
	var melee_attack_active: bool = weapon_controller != null and weapon_controller.has_method("is_melee_attack_anim_active") and weapon_controller.is_melee_attack_anim_active()

	for visual_slot in equipment_visual_slots:
		if not visual_slot.visible:
			continue

		if visual_slot.sprite_frames == null:
			continue

		if _is_switchable_weapon_slot(visual_slot.item_type) and visual_slot.item_type != active_weapon_slot:
			continue

		if melee_attack_active and visual_slot.item_type == ItemData.ItemType.MeleeWeapon:
			continue

		_apply_equipment_animation(visual_slot, animation_name)


func _apply_equipment_animation(visual_slot: EquipmentVisualSlot, requested_animation: String) -> void:
	if visual_slot == null or visual_slot.sprite_frames == null:
		return

	var target_animation: String = _get_equipment_animation_name(visual_slot.sprite_frames, requested_animation)
	if target_animation == "":
		visual_slot.stop()
		return

	visual_slot.play(target_animation)
	var target_frame_count: int = visual_slot.sprite_frames.get_frame_count(target_animation)
	if target_frame_count > 0:
		visual_slot.frame = clamp(anim.frame, 0, target_frame_count - 1)
	visual_slot.speed_scale = _get_current_animation_speed_scale()


func _get_equipment_animation_name(frames: SpriteFrames, requested_animation: String) -> String:
	if frames == null:
		return ""
	if frames.has_animation(requested_animation):
		return requested_animation
	if requested_animation.ends_with("_weapon"):
		var base_idle_animation: String = requested_animation.trim_suffix("_weapon")
		if frames.has_animation(base_idle_animation):
			return base_idle_animation
	if requested_animation.begins_with("Aim_"):
		var fallback_animation: String = "Idle_" + requested_animation.trim_prefix("Aim_")
		if frames.has_animation(fallback_animation):
			return fallback_animation
	return ""


func _update_scope_overlay_for_slot(visual_slot: EquipmentVisualSlot, equipped_item: ItemData, animation_name: String) -> void:
	if visual_slot == null:
		return
	if not visual_slot.has_method("set_scope_overlay"):
		return
	if equipped_item == null or equipped_item.storage_category != ItemData.StorageCategory.WEAPON:
		visual_slot.clear_scope_overlay()
		return

	var attached_scope: ItemData = InventoryManager.get_attached_scope(equipped_item)
	if attached_scope == null:
		visual_slot.clear_scope_overlay()
		return

	var scope_texture: Texture2D = attached_scope.get_attachment_mounted_texture() if attached_scope.has_method("get_attachment_mounted_texture") else attached_scope.mounted_scope_texture
	if scope_texture == null:
		scope_texture = attached_scope.inventory_icon
	if scope_texture == null:
		visual_slot.clear_scope_overlay()
		return

	var alignment: Dictionary = _get_weapon_scope_alignment(equipped_item, animation_name)
	visual_slot.set_scope_overlay(
		scope_texture,
		alignment.get("offset", Vector2.ZERO),
		alignment.get("scale", attached_scope.mounted_scope_scale),
		float(alignment.get("rotation", attached_scope.mounted_scope_rotation_degrees)),
		visual_slot.visible
	)


func _get_weapon_scope_alignment(_weapon: ItemData, _animation_name: String) -> Dictionary:
	return {
		"offset": Vector2.ZERO,
		"scale": Vector2.ONE,
		"rotation": 0.0
	}


func movement_loop(delta: float) -> void:
	if movement_controller != null:
		movement_controller.movement_loop(delta, inventory_root, weapon_controller)


func _update_aim_movement_animation(input_vector: Vector2) -> void:
	var aim_dir: String = weapon_controller.get_aim_direction_4way()
	facing_direction = aim_dir

	if input_vector == Vector2.ZERO:
		_set_idle_dir_from_string(aim_dir)
		_play_body_animation_if_exists("Aim_" + aim_dir)
		return

	update_move_animation(input_vector)


func _play_body_animation_if_exists(animation_name: String) -> void:
	if anim.sprite_frames == null:
		return

	if anim.sprite_frames.has_animation(animation_name):
		anim.play(animation_name)
		anim.speed_scale = _get_current_animation_speed_scale()
		_sync_equipment_animation(animation_name)


func _play_action_animation_if_available() -> bool:
	if current_action_animation.is_empty():
		return false
	if anim == null or anim.sprite_frames == null:
		return false
	if not anim.sprite_frames.has_animation(current_action_animation):
		return false

	anim.play(current_action_animation)
	anim.speed_scale = _get_current_animation_speed_scale()
	_sync_equipment_animation(current_action_animation)
	return true


func _set_idle_dir_from_string(dir: String) -> void:
	match dir:
		"down":
			idle_dir = DOWN
		"up":
			idle_dir = UP
		"left":
			idle_dir = LEFT
		"right":
			idle_dir = RIGHT


func take_damage(amount: float, damage_type: int = ItemData.DamageType.GENERIC, apply_clothing_damage: bool = true) -> void:
	if vitals_controller != null:
		vitals_controller.take_damage(amount, damage_type, apply_clothing_damage)


func take_damage_from(amount: float, source: Node, hit_context: Dictionary = {}) -> void:
	take_damage(amount, _resolve_damage_type_from_source(source), true)
	if is_dead:
		return
	if amount > 0.0:
		if blood_effects_controller != null:
			blood_effects_controller.spawn_hit_blood(source, hit_context)

	if source != null and source.is_in_group("bandit"):
		if randf() <= clamp(fracture_from_bandit_chance, 0.0, 1.0):
			_set_fractured(true)


func take_enemy_damage(amount: float, bleed_chance: float = 0.25, damage_type: int = ItemData.DamageType.BITE) -> void:
	take_damage(amount, damage_type, true)
	if is_dead:
		return
	if amount > 0.0:
		if blood_effects_controller != null:
			blood_effects_controller.spawn_hit_blood(null, {})

	if randf() <= clamp(bleed_chance, 0.0, 1.0):
		_set_bleeding(true)


func _apply_clothing_endurance_from_damage(amount: float, damage_type: int) -> void:
	if InventoryManager == null:
		return
	InventoryManager.apply_damage_to_equipped_clothing(amount, damage_type)


func _resolve_damage_type_from_source(source: Node) -> int:
	if source == null:
		return incoming_default_damage_type
	if _source_matches_any_group(source, incoming_bullet_source_groups):
		return ItemData.DamageType.BULLET
	if _source_matches_any_group(source, incoming_bite_source_groups):
		return ItemData.DamageType.BITE
	if _source_matches_any_group(source, incoming_melee_source_groups):
		return ItemData.DamageType.MELEE
	if _source_matches_any_group(source, incoming_explosion_source_groups):
		return ItemData.DamageType.EXPLOSION
	return incoming_default_damage_type


func _source_matches_any_group(source: Node, groups: Array[StringName]) -> bool:
	if source == null or groups.is_empty():
		return false

	for group_name in groups:
		if group_name.is_empty():
			continue
		if source.is_in_group(group_name):
			return true

	return false


func die() -> void:
	if death_effects_controller != null:
		death_effects_controller.die()


func _setup_walk_snow_sfx() -> void:
	if walk_snow_sfx == null:
		return

	if walk_snow_sfx.stream == null:
		walk_snow_sfx.stream = WALK_SNOW_STREAM

	if AudioServer.get_bus_index(&"Sounds") != -1:
		walk_snow_sfx.bus = &"Sounds"
	else:
		walk_snow_sfx.bus = &"Master"

	var wav_stream: AudioStreamWAV = walk_snow_sfx.stream as AudioStreamWAV
	if wav_stream != null:
		wav_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD


func _update_walk_snow_sfx(input_vector: Vector2, delta: float) -> void:
	if walk_snow_sfx == null:
		return

	if walk_snow_min_play_time_left > 0.0:
		walk_snow_min_play_time_left = max(walk_snow_min_play_time_left - delta, 0.0)

	var should_play: bool = input_vector.length() > WALK_SNOW_MIN_MOVE_LENGTH and velocity.length() > WALK_SNOW_MIN_MOVE_LENGTH
	if should_play:
		walk_snow_min_play_time_left = WALK_SNOW_MIN_PLAY_SECONDS
		if not walk_snow_sfx.playing:
			walk_snow_sfx.play()
	else:
		if walk_snow_min_play_time_left <= 0.0:
			_stop_walk_snow_sfx()


func _stop_walk_snow_sfx() -> void:
	if walk_snow_sfx != null and walk_snow_sfx.playing:
		walk_snow_sfx.stop()


func _go_to_menu(save_before_exit: bool = true) -> void:
	if save_before_exit and GameSaveManager != null and GameSaveManager.has_method("save_game"):
		GameSaveManager.save_game()
	get_tree().change_scene_to_file("res://Menu/Menu.tscn")


func add_water(amount: float) -> void:
	if vitals_controller != null:
		vitals_controller.add_water(amount)


func add_food(amount: float) -> void:
	if vitals_controller != null:
		vitals_controller.add_food(amount)


func add_health(amount: float) -> void:
	if vitals_controller != null:
		vitals_controller.add_health(amount)


func add_radiation(amount: float) -> void:
	if vitals_controller != null:
		vitals_controller.add_radiation(amount)


func apply_medical_item_effect(item: ItemData) -> bool:
	if item == null:
		return false
	if item.storage_category != ItemData.StorageCategory.MEDICAL:
		return false
	return vitals_controller != null and vitals_controller.apply_medical_item_effect(item)


func add_stamina(amount: float) -> void:
	if vitals_controller != null:
		vitals_controller.add_stamina(amount)


func _set_bleeding(value: bool) -> void:
	if vitals_controller != null:
		vitals_controller.set_bleeding(value)


func _set_fractured(value: bool) -> void:
	if vitals_controller != null:
		vitals_controller.set_fractured(value)


func try_apply_food_poison(chance: float, custom_duration: float = -1.0) -> bool:
	return vitals_controller != null and vitals_controller.try_apply_food_poison(chance, custom_duration)


func _set_diseased(value: bool, duration_sec: float = -1.0) -> void:
	if vitals_controller != null:
		vitals_controller.set_diseased(value, duration_sec)


func has_passive_regeneration() -> bool:
	return vitals_controller != null and vitals_controller.has_passive_regeneration()


func start_timed_action(duration: float, on_complete: Callable, _label: String = "", blocks_movement: bool = true, action_animation_name: String = "") -> bool:
	return timed_action_controller != null and timed_action_controller.start_timed_action(duration, on_complete, _label, blocks_movement, action_animation_name)


func cancel_timed_action(expected_callback: Callable = Callable()) -> bool:
	return timed_action_controller != null and timed_action_controller.cancel_timed_action(expected_callback)


func _update_timed_action(delta: float) -> void:
	if timed_action_controller != null:
		timed_action_controller.update_timed_action(delta)


func _show_action_bar(duration: float) -> void:
	if timed_action_controller != null:
		timed_action_controller.show_action_bar(duration)


func _set_action_progress(progress_ratio: float) -> void:
	if timed_action_controller != null:
		timed_action_controller.set_action_progress(progress_ratio)


func _hide_action_bar() -> void:
	if timed_action_controller != null:
		timed_action_controller.hide_action_bar()


func _ensure_status_hint_label() -> void:
	if status_hint_controller != null:
		status_hint_controller.ensure_status_hint_label()


func _update_low_need_hints(delta: float) -> void:
	if status_hint_controller != null:
		status_hint_controller.update_low_need_hints(delta)


func _enqueue_status_hint(text: String, color: Color) -> void:
	if status_hint_controller != null:
		status_hint_controller.enqueue_status_hint(text, color)


func _start_status_hint(hint_data: Dictionary) -> void:
	if status_hint_controller != null:
		status_hint_controller.start_status_hint(hint_data)


func _update_status_hint_visual(delta: float) -> void:
	if status_hint_controller != null:
		status_hint_controller.update_status_hint_visual(delta)


func update_move_animation(input_vector: Vector2) -> void:
	if abs(input_vector.x) > abs(input_vector.y):
		if input_vector.x > 0.0:
			right_move()
		else:
			left_move()
	else:
		if input_vector.y > 0.0:
			down_move()
		else:
			up_move()


func up_move() -> void:
	anim.play("Up")
	anim.speed_scale = _get_current_animation_speed_scale()
	_sync_equipment_animation("Up")
	idle_dir = UP
	facing_direction = "up"


func down_move() -> void:
	anim.play("Down")
	anim.speed_scale = _get_current_animation_speed_scale()
	_sync_equipment_animation("Down")
	idle_dir = DOWN
	facing_direction = "down"


func left_move() -> void:
	anim.play("Left")
	anim.speed_scale = _get_current_animation_speed_scale()
	_sync_equipment_animation("Left")
	idle_dir = LEFT
	facing_direction = "left"


func right_move() -> void:
	anim.play("Right")
	anim.speed_scale = _get_current_animation_speed_scale()
	_sync_equipment_animation("Right")
	idle_dir = RIGHT
	facing_direction = "right"


func idle() -> void:
	var idle_animation_name: String = _get_idle_body_animation_name()

	match idle_dir:
		DOWN:
			anim.play(idle_animation_name if idle_animation_name.begins_with("Idle_down") else "Idle_down")
			anim.speed_scale = _get_idle_animation_speed_scale()
			_sync_equipment_animation(String(anim.animation))
		UP:
			anim.play(idle_animation_name if idle_animation_name.begins_with("Idle_up") else "Idle_up")
			anim.speed_scale = _get_idle_animation_speed_scale()
			_sync_equipment_animation(String(anim.animation))
		LEFT:
			anim.play(idle_animation_name if idle_animation_name.begins_with("Idle_left") else "Idle_left")
			anim.speed_scale = _get_idle_animation_speed_scale()
			_sync_equipment_animation(String(anim.animation))
		RIGHT:
			anim.play(idle_animation_name if idle_animation_name.begins_with("Idle_right") else "Idle_right")
			anim.speed_scale = _get_idle_animation_speed_scale()
			_sync_equipment_animation(String(anim.animation))


func _get_idle_body_animation_name() -> String:
	var base_animation: String = "Idle_down"
	match idle_dir:
		UP:
			base_animation = "Idle_up"
		LEFT:
			base_animation = "Idle_left"
		RIGHT:
			base_animation = "Idle_right"

	if weapon_controller != null and weapon_controller.has_weapon_equipped():
		var weapon_idle_animation: String = base_animation + "_weapon"
		if anim != null and anim.sprite_frames != null and anim.sprite_frames.has_animation(weapon_idle_animation):
			return weapon_idle_animation

	return base_animation


func _force_refresh_animation() -> void:
	if action_in_progress and action_blocks_movement and _play_action_animation_if_available():
		return

	if weapon_controller.is_in_aim_mode() and weapon_controller.has_weapon_equipped():
		_update_aim_movement_animation(velocity.normalized())
	else:
		if velocity == Vector2.ZERO:
			idle()
		else:
			update_move_animation(velocity.normalized())


func _is_switchable_weapon_slot(slot_type: ItemData.ItemType) -> bool:
	return slot_type in [
		ItemData.ItemType.AR_Weapon,
		ItemData.ItemType.Pistols,
		ItemData.ItemType.MeleeWeapon
	]


func _get_stamina_ratio() -> float:
	if max_stamina <= 0.0:
		return 1.0

	return clamp(stamina / max_stamina, 0.0, 1.0)


func _get_current_speed_multiplier() -> float:
	var stamina_multiplier: float = lerp(min_exhausted_speed_multiplier, 1.0, _get_stamina_ratio())
	var stealth_multiplier: float = _get_stealth_movement_multiplier()
	if is_fractured:
		return stamina_multiplier * stealth_multiplier * clamp(fracture_speed_multiplier, 0.0, 1.0)
	return stamina_multiplier * stealth_multiplier


func _get_current_animation_speed_scale() -> float:
	var stamina_animation: float = lerp(min_exhausted_animation_multiplier, 1.0, _get_stamina_ratio())
	return base_animation_speed_scale * stamina_animation * _get_stealth_animation_multiplier()


func _get_idle_animation_speed_scale() -> float:
	return base_animation_speed_scale * _get_stealth_animation_multiplier()


func _get_stealth_movement_multiplier() -> float:
	if not is_stealth:
		return 1.0
	return clamp(stealth_speed_multiplier, 0.05, 1.0)


func _get_stealth_animation_multiplier() -> float:
	if not is_stealth:
		return 1.0
	return clamp(stealth_animation_multiplier, 0.05, 1.0)


func _get_stealth_noise_multiplier() -> float:
	if not is_stealth:
		return 1.0
	return clamp(stealth_noise_multiplier, 0.05, 1.0)


func _update_stealth_state() -> void:
	if movement_controller == null:
		return
	var stealth_state: Dictionary = movement_controller.update_stealth_state(stealth_action_name, base_noise_level, stealth_noise_multiplier)
	is_stealth = bool(stealth_state.get("is_stealth", false))
	current_noise_level = float(stealth_state.get("current_noise_level", base_noise_level))


func get_noise_loudness_multiplier() -> float:
	return _get_stealth_noise_multiplier()


func is_in_stealth_mode() -> bool:
	return is_stealth


func get_current_noise_level() -> float:
	return current_noise_level


func set_current_noise_level(value: float) -> void:
	current_noise_level = max(value, 0.0)


func _apply_current_animation_speed(is_idle: bool) -> void:
	if is_idle:
		anim.speed_scale = _get_idle_animation_speed_scale()
	else:
		anim.speed_scale = _get_current_animation_speed_scale()

	for visual_slot in equipment_visual_slots:
		if not visual_slot.visible:
			continue

		visual_slot.speed_scale = anim.speed_scale


func _trigger_secondary_interaction() -> bool:
	return interaction_controller != null and interaction_controller.trigger_secondary_interaction()


func _trigger_primary_interaction() -> bool:
	return interaction_controller != null and interaction_controller.trigger_primary_interaction()


func _update_bleeding_trail(delta: float) -> void:
	if blood_effects_controller != null:
		blood_effects_controller.update_bleeding_trail(delta)


func get_save_key() -> String:
	return "player:main"


func get_save_data() -> Dictionary:
	return {
		"global_position": {"x": global_position.x, "y": global_position.y},
		"health": health,
		"water": water,
		"food": food,
		"stamina": stamina,
		"radiation": radiation,
		"is_bleeding": is_bleeding,
		"is_fractured": is_fractured,
		"is_diseased": is_diseased,
		"disease_time_left": disease_time_left,
		"water_timer": water_timer,
		"food_timer": food_timer,
		"bleeding_timer": bleeding_timer,
		"disease_tick_timer": disease_tick_timer
	}


func apply_save_data(save_data: Dictionary) -> void:
	var position_data: Dictionary = save_data.get("global_position", {})
	if not position_data.is_empty():
		global_position = Vector2(
			float(position_data.get("x", global_position.x)),
			float(position_data.get("y", global_position.y))
		)

	health = clamp(float(save_data.get("health", health)), 0.0, max_health)
	water = clamp(float(save_data.get("water", water)), 0.0, max_water)
	food = clamp(float(save_data.get("food", food)), 0.0, max_food)
	stamina = clamp(float(save_data.get("stamina", stamina)), 0.0, max_stamina)
	radiation = max(float(save_data.get("radiation", radiation)), 0.0)

	is_bleeding = bool(save_data.get("is_bleeding", is_bleeding))
	is_fractured = bool(save_data.get("is_fractured", is_fractured))
	is_diseased = bool(save_data.get("is_diseased", is_diseased))
	disease_time_left = max(float(save_data.get("disease_time_left", disease_time_left)), 0.0)

	water_timer = max(float(save_data.get("water_timer", water_timer)), 0.0)
	food_timer = max(float(save_data.get("food_timer", food_timer)), 0.0)
	bleeding_timer = max(float(save_data.get("bleeding_timer", bleeding_timer)), 0.0)
	disease_tick_timer = max(float(save_data.get("disease_tick_timer", disease_tick_timer)), 0.0)

	if not is_bleeding:
		bleeding_trail_timer = 0.0

	stats_changed.emit()
	status_effects_changed.emit()
