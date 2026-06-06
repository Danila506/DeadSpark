extends CharacterBody2D

signal stats_changed
signal status_effects_changed

@export var max_health: float = 100.0
@export var max_water: float = 100.0
@export var max_food: float = 100.0
@export var max_stamina: float = 100.0
@export var debug_invulnerable: bool = false

var health: float = 100.0
var water: float = 100.0
var food: float = 100.0
var stamina: float = 100.0
var radiation: float = 0.0
var is_bleeding: bool = false
var is_fractured: bool = false
var is_diseased: bool = false

@export var water_drain_amount: float = 4.0
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
@export var carry_weight_soft_limit: float = 25.0
@export var carry_weight_hard_limit: float = 45.0
@export_range(0.05, 1.0, 0.01) var carry_weight_update_interval_sec: float = 0.20
@export_range(0.05, 1.0, 0.01) var overloaded_speed_multiplier: float = 0.55
@export_range(1.0, 5.0, 0.05) var overloaded_stamina_drain_multiplier: float = 2.25
@export_range(0.0, 1.0, 0.01) var overloaded_stamina_recovery_multiplier: float = 0.45
@export_range(1.0, 5.0, 0.05) var overloaded_noise_multiplier: float = 1.6
@export_range(0.0, 1.0, 0.01) var fracture_speed_multiplier: float = 0.5
@export_range(0.0, 1.0, 0.01) var fracture_from_bandit_chance: float = 0.05
@export var incoming_bullet_source_groups: Array[StringName] = [&"bandit"]
@export var incoming_bite_source_groups: Array[StringName] = [&"wolf"]
@export var incoming_melee_source_groups: Array[StringName] = [&"enemy"]
@export var incoming_explosion_source_groups: Array[StringName] = []
@export var incoming_default_damage_type: int = ItemData.DamageType.GENERIC
@export_category("Network Smoothing")
@export_range(0.02, 0.30, 0.005) var net_snapshot_interp_delay_sec: float = 0.10
@export_range(0.10, 1.00, 0.01) var net_snapshot_max_buffer_sec: float = 0.50
@export_category("Lag Compensation")
@export_range(0.20, 2.00, 0.01) var net_lag_history_duration_sec: float = 0.75
@export_range(0.005, 0.100, 0.001) var net_lag_history_sample_interval_sec: float = 0.016

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
var _last_equipment_animation: String = ""
var _last_equipment_active_weapon_slot: int = -1
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
var current_carry_weight: float = 0.0
var current_encumbrance_ratio: float = 0.0
var _carry_weight_refresh_timer: float = 0.0
var peer_id: int = 1
var _net_target_position: Vector2 = Vector2.ZERO
var _net_target_velocity: Vector2 = Vector2.ZERO
var _net_can_send_updates: bool = false
var _net_last_remote_update_ms: int = 0
var _net_last_remote_position: Vector2 = Vector2.ZERO
var _net_input_vector: Vector2 = Vector2.ZERO
var _net_input_seq: int = 0
var _net_last_applied_input_seq: int = -1
var _net_last_server_ack_seq: int = -1
var _net_snapshot_buffer: Array[Dictionary] = []
var _net_server_time_offset_sec: float = 0.0
var _net_server_time_offset_initialized: bool = false
var _net_lag_history_samples: Array[Dictionary] = []
var _net_lag_history_sample_timer: float = 0.0
var _net_vitals_sync_timer: float = 0.0
var _collision_exception_refresh_timer: float = 0.0
var _net_equipment_sync_timer: float = 0.0
var _net_state_sync_timer_by_peer: Dictionary = {}
var _net_state_tick_elapsed_sec: float = 0.0
var _net_vitals_tick_elapsed_sec: float = 0.0
var _net_equipment_tick_elapsed_sec: float = 0.0
var _net_remote_active_weapon_slot: int = ItemData.ItemType.AR_Weapon
var _net_remote_equipped_paths: Dictionary = {}
var _net_item_definition_cache: Dictionary = {}
var _net_last_sent_equipment_signature: String = ""
var _net_last_sent_equipment_signature_by_peer: Dictionary = {}
var _net_reported_active_weapon_slot: int = ItemData.ItemType.AR_Weapon
var _net_reported_equipped_paths: Dictionary = {}
var _net_reported_equipment_initialized: bool = false
var _pause_menu_layer: CanvasLayer = null
var _pause_menu_root: Control = null
var _pause_menu_panel: PanelContainer = null
var _pause_continue_button: Button = null
var _pause_main_menu_button: Button = null
var _lan_smoke_net_debug: bool = false
var _lan_net_debug_enabled: bool = false
var _net_debug_log_timer_sec: float = 0.0
var _net_debug_correction_count: int = 0
var _net_debug_correction_sum_px: float = 0.0
var _net_debug_correction_max_px: float = 0.0
var _net_debug_snap_count: int = 0
var _net_debug_snapshot_count: int = 0
var _net_debug_snapshot_gap_sum_ms: float = 0.0
var _net_debug_snapshot_gap_max_ms: float = 0.0
var _net_debug_last_snapshot_recv_ms: int = 0
var _net_debug_server_input_count: int = 0
var _net_debug_server_input_gap_sum_ms: float = 0.0
var _net_debug_server_input_gap_max_ms: float = 0.0
var _net_debug_server_last_input_recv_ms: int = 0
var _net_server_last_input_recv_ms: int = 0
var _net_server_smoothed_input: Vector2 = Vector2.ZERO
var _net_server_last_nonzero_input: Vector2 = Vector2.ZERO
var _net_client_input_send_timer_sec: float = 0.0
var _net_client_state_send_timer_sec: float = 0.0
var _net_state_seq: int = 0
var _net_last_applied_state_seq: int = -1
var _net_server_last_state_recv_ms: int = 0
var _net_server_last_state_position: Vector2 = Vector2.ZERO
var _net_server_last_state_velocity: Vector2 = Vector2.ZERO
var _net_server_has_state: bool = false
var _net_debug_server_state_count: int = 0
var _net_debug_server_state_gap_sum_ms: float = 0.0
var _net_debug_server_state_gap_max_ms: float = 0.0
var _net_debug_server_last_state_recv_ms: int = 0

@export var net_eq_active_weapon_slot: int = ItemData.ItemType.AR_Weapon:
	set(value):
		net_eq_active_weapon_slot = value
		_on_replicated_equipment_changed()
@export var net_eq_ar_path: String = "":
	set(value):
		net_eq_ar_path = value
		_on_replicated_equipment_changed()
@export var net_eq_pistol_path: String = "":
	set(value):
		net_eq_pistol_path = value
		_on_replicated_equipment_changed()
@export var net_eq_melee_path: String = "":
	set(value):
		net_eq_melee_path = value
		_on_replicated_equipment_changed()
@export var net_eq_tshirt_path: String = "":
	set(value):
		net_eq_tshirt_path = value
		_on_replicated_equipment_changed()
@export var net_eq_jacket_path: String = "":
	set(value):
		net_eq_jacket_path = value
		_on_replicated_equipment_changed()
@export var net_eq_heavy_path: String = "":
	set(value):
		net_eq_heavy_path = value
		_on_replicated_equipment_changed()
@export var net_eq_trousers_path: String = "":
	set(value):
		net_eq_trousers_path = value
		_on_replicated_equipment_changed()
@export var net_eq_bag_path: String = "":
	set(value):
		net_eq_bag_path = value
		_on_replicated_equipment_changed()
@export var net_eq_cap_path: String = "":
	set(value):
		net_eq_cap_path = value
		_on_replicated_equipment_changed()

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
const NET_MAX_POSITION_DELTA_PER_UPDATE: float = 96.0
const NET_MAX_SPEED: float = 420.0
const NET_MIN_UPDATE_INTERVAL_MS: int = 16
const NET_RECONCILE_SOFT_DEADZONE: float = 4.0
const NET_RECONCILE_SOFT_BLEND_ALPHA: float = 0.18
const NET_RECONCILE_VELOCITY_BLEND_ALPHA: float = 0.25
const NET_RECONCILE_HARD_SNAP_DISTANCE: float = 160.0
const NET_ENABLE_STATE_SYNC: bool = true
const NET_SERVER_INPUT_STALE_TIMEOUT_MS: int = 140
const NET_SERVER_INPUT_SMOOTH_ALPHA: float = 0.22
const NET_SERVER_INPUT_HOLD_MS: int = 260
const NET_CLIENT_INPUT_SEND_INTERVAL_SEC: float = 1.0 / 30.0
const NET_CLIENT_STATE_SEND_INTERVAL_SEC: float = 1.0 / 20.0
const NET_SERVER_STATE_STALE_TIMEOUT_MS: int = 700
const NET_SERVER_STATE_HARD_TIMEOUT_MS: int = 2200
const NET_SERVER_STATE_MAX_DELTA_PER_UPDATE: float = 120.0
const NET_SERVER_STATE_MAX_DELTA_MARGIN_PX: float = 24.0
const NET_SERVER_STATE_MAX_ELAPSED_SEC: float = 0.35
const NET_SERVER_STATE_POSITION_BLEND: float = 0.55
const NET_SERVER_STATE_EXTRAPOLATION_MAX_SEC: float = 0.12
const NET_INPUT_ACTIONS_PRIMARY: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]
const NET_INPUT_ACTIONS_FALLBACK: Array[StringName] = [&"left", &"right", &"up", &"down"]
const NET_VITALS_SYNC_INTERVAL_SEC: float = 0.10
const NET_EQUIPMENT_SYNC_INTERVAL_SEC: float = 0.25
const NET_STATE_SYNC_INTERVAL_NEAR_SEC: float = 0.033
const NET_STATE_SYNC_INTERVAL_FAR_SEC: float = 0.10
const NET_STATE_SYNC_FAR_DISTANCE_PX: float = 1400.0
const COLLISION_EXCEPTION_REFRESH_INTERVAL_SEC: float = 1.0
const NET_SNAPSHOT_POS_SCALE: float = 10.0
const NET_SNAPSHOT_VEL_SCALE: float = 10.0
const NET_SNAPSHOT_HEALTH_SCALE: float = 100.0
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


func _enter_tree() -> void:
	_setup_equipment_synchronizer()


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
	_update_carry_weight_state()
	stats_changed.emit()
	_collect_equipment_visual_slots()
	_connect_inventory_signals()
	_refresh_equipment_visuals()
	_force_refresh_animation()
	_hide_action_bar()
	_ensure_status_hint_label()
	_net_target_position = global_position
	_net_target_velocity = Vector2.ZERO
	_net_server_smoothed_input = Vector2.ZERO
	_net_server_last_nonzero_input = Vector2.ZERO
	_net_client_input_send_timer_sec = 0.0
	_net_client_state_send_timer_sec = 0.0
	_net_last_remote_position = global_position
	_net_server_last_state_position = global_position
	_net_last_remote_update_ms = Time.get_ticks_msec()
	_net_can_send_updates = not _is_networked_game()
	if camera_2d != null and _is_networked_game():
		camera_2d.enabled = _is_local_network_player()
	_lan_smoke_net_debug = _has_cli_flag("lan-smoke-log-eq")
	_lan_net_debug_enabled = _has_cli_flag("lan-net-debug")
	print("Local player authority true/false for peer %d: %s" % [peer_id, str(is_multiplayer_authority())])
	if _is_networked_game() and _is_local_network_player():
		call_deferred("_enable_network_updates_after_spawn_sync")
	if GameSaveManager != null and GameSaveManager.has_method("register_persistent_node") and _is_local_control_enabled():
		GameSaveManager.register_persistent_node(self)
	if NetworkManager != null and NetworkManager.has_signal("network_tick"):
		if not NetworkManager.network_tick.is_connected(_on_network_tick):
			NetworkManager.network_tick.connect(_on_network_tick)
	call_deferred("_refresh_non_blocking_collision_exceptions")


func _exit_tree() -> void:
	if NetworkManager != null and NetworkManager.has_signal("network_tick"):
		if NetworkManager.network_tick.is_connected(_on_network_tick):
			NetworkManager.network_tick.disconnect(_on_network_tick)
	get_tree().paused = false
	if _pause_menu_layer != null and is_instance_valid(_pause_menu_layer):
		_pause_menu_layer.queue_free()
	_pause_menu_layer = null
	_pause_menu_root = null
	_pause_menu_panel = null
	_pause_continue_button = null
	_pause_main_menu_button = null


func _resolve_walk_snow_sfx() -> AudioStreamPlayer:
	var from_audio_node: AudioStreamPlayer = get_node_or_null("Audio/SnowWalk") as AudioStreamPlayer
	if from_audio_node != null:
		return from_audio_node
	return get_node_or_null("SnowWalk") as AudioStreamPlayer


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_control_enabled():
		return
	if is_dead:
		return

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		call_deferred("_toggle_pause_menu")
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey

		if key_event.physical_keycode == KEY_E:
			if try_primary_interaction():
				get_viewport().set_input_as_handled()
				return

		if key_event.physical_keycode == KEY_F:
			if try_secondary_interaction():
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


func _physics_process(delta: float) -> void:
	if _lan_net_debug_enabled:
		_net_debug_log_timer_sec += maxf(delta, 0.0)
		if _net_debug_log_timer_sec >= 1.0:
			_net_debug_log_timer_sec = 0.0
			_emit_network_debug_metrics()

	if _is_networked_game():
		_collision_exception_refresh_timer -= delta
		if _collision_exception_refresh_timer <= 0.0:
			_collision_exception_refresh_timer = COLLISION_EXCEPTION_REFRESH_INTERVAL_SEC
			_refresh_non_blocking_collision_exceptions()
		if NetworkManager != null and NetworkManager.is_server():
			_record_lag_history_sample_if_due(delta)
			if peer_id > 1 and not _is_network_peer_still_connected(peer_id):
				return
			if is_dead:
				return
			_update_carry_weight_state_if_due(delta)
			_update_stealth_state()
			var server_input: Vector2 = _net_input_vector
			if _is_local_network_player():
				server_input = _get_network_input_vector()
			else:
				if NET_ENABLE_STATE_SYNC and _net_server_has_state:
					_apply_server_received_state()
					return
				var now_ms: int = Time.get_ticks_msec()
				var input_age_ms: int = now_ms - _net_server_last_input_recv_ms
				if server_input.length_squared() > 0.0001:
					_net_server_last_nonzero_input = server_input
				elif input_age_ms <= NET_SERVER_INPUT_HOLD_MS and _net_server_last_nonzero_input.length_squared() > 0.0001:
					server_input = _net_server_last_nonzero_input
				if input_age_ms > NET_SERVER_INPUT_STALE_TIMEOUT_MS * 2:
					server_input = Vector2.ZERO
					_net_server_last_nonzero_input = Vector2.ZERO
				_net_server_smoothed_input = _net_server_smoothed_input.lerp(server_input, NET_SERVER_INPUT_SMOOTH_ALPHA)
				server_input = _net_server_smoothed_input
			_apply_network_movement(delta, server_input)
			return

		if _is_local_network_player():
			if is_dead:
				return
			_update_carry_weight_state_if_due(delta)
			_update_stealth_state()
			var local_input: Vector2 = _get_network_input_vector()
			_apply_network_movement(delta, local_input)
			if _net_can_send_updates:
				_net_client_input_send_timer_sec -= maxf(delta, 0.0)
				if _net_client_input_send_timer_sec <= 0.0:
					_net_client_input_send_timer_sec = NET_CLIENT_INPUT_SEND_INTERVAL_SEC
					rpc_id(1, "rpc_submit_input", local_input, _net_input_seq)
					_net_input_seq += 1
				if NET_ENABLE_STATE_SYNC:
					_net_client_state_send_timer_sec -= maxf(delta, 0.0)
					if _net_client_state_send_timer_sec <= 0.0:
						_net_client_state_send_timer_sec = NET_CLIENT_STATE_SEND_INTERVAL_SEC
						rpc_id(1, "rpc_submit_state", global_position, velocity, _net_state_seq)
						_net_state_seq += 1
			return

		_apply_remote_snapshot_interpolation()
		if velocity.length() <= 0.01:
			idle()
		else:
			update_move_animation(velocity.normalized())
		return

	if is_dead:
		return

	_update_carry_weight_state_if_due(delta)
	_update_stealth_state()
	movement_loop(delta)


func _process(delta: float) -> void:
	if not _is_local_control_enabled():
		return
	if is_dead:
		return

	_update_needs(delta)
	_update_stamina(delta)
	_update_timed_action(delta)
	_update_low_need_hints(delta)
	_update_status_hint_visual(delta)
	_update_bleeding_trail(delta)


func _on_network_tick(tick_delta_sec: float, _tick_id: int) -> void:
	if not _is_networked_game() or NetworkManager == null:
		return
	if not NetworkManager.is_server():
		return
	if is_dead:
		return

	_net_state_tick_elapsed_sec += tick_delta_sec
	if _net_state_tick_elapsed_sec >= 0.001:
		_broadcast_player_snapshot_interest(_net_state_tick_elapsed_sec)
		_net_state_tick_elapsed_sec = 0.0


func _update_needs(delta: float) -> void:
	if vitals_controller != null:
		vitals_controller.update_needs(delta)


func _update_stamina(delta: float) -> void:
	if vitals_controller != null:
		vitals_controller.update_stamina(delta, inventory_root)


func _collect_equipment_visual_slots() -> void:
	equipment_visual_slots.clear()
	_find_equipment_visual_slots_recursive(self)
	_apply_equipment_visual_layering()


func _find_equipment_visual_slots_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is EquipmentVisualSlot:
			equipment_visual_slots.append(child)

		_find_equipment_visual_slots_recursive(child)


func _apply_equipment_visual_layering() -> void:
	for visual_slot in equipment_visual_slots:
		if visual_slot == null:
			continue
		visual_slot.z_as_relative = true
		visual_slot.z_index = _get_equipment_layer_z_index(visual_slot.item_type)


func _get_equipment_layer_z_index(slot_type: int) -> int:
	match slot_type:
		ItemData.ItemType.T_shirts:
			return 0
		ItemData.ItemType.Jacket:
			return 0
		ItemData.ItemType.HeavyArmour:
			return 0
		ItemData.ItemType.Bag:
			return 0
		ItemData.ItemType.Cap:
			return 0
		ItemData.ItemType.Trousers:
			return 0
		ItemData.ItemType.AR_Weapon, ItemData.ItemType.Pistols, ItemData.ItemType.MeleeWeapon, ItemData.ItemType.Lefthand:
			return 0
		_:
			return 0


func _connect_inventory_signals() -> void:
	if not InventoryManager.equipment_changed.is_connected(_on_equipment_changed):
		InventoryManager.equipment_changed.connect(_on_equipment_changed)


func _on_equipment_changed(_slot_type: int, _item: ItemData) -> void:
	_update_carry_weight_state()
	_publish_local_equipment_state_to_replication()
	_refresh_equipment_visuals()
	_force_refresh_animation()


func _refresh_equipment_visuals() -> void:
	if _is_networked_game() and not _is_local_network_player():
		_apply_remote_equipment_visuals()
		return
	var active_weapon_slot: int = InventoryManager.get_active_weapon_slot()
	_last_equipment_active_weapon_slot = active_weapon_slot
	_last_equipment_animation = ""

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
	var is_remote_network_player: bool = _is_networked_game() and not _is_local_network_player()
	var active_weapon_slot: int = _net_remote_active_weapon_slot if is_remote_network_player else InventoryManager.get_active_weapon_slot()
	var melee_attack_active: bool = false
	if not is_remote_network_player:
		melee_attack_active = weapon_controller != null and weapon_controller.has_method("is_melee_attack_anim_active") and weapon_controller.is_melee_attack_anim_active()
	var equipment_state_changed: bool = animation_name != _last_equipment_animation or active_weapon_slot != _last_equipment_active_weapon_slot
	if equipment_state_changed:
		_last_equipment_animation = animation_name
		_last_equipment_active_weapon_slot = active_weapon_slot

	for visual_slot in equipment_visual_slots:
		if not visual_slot.visible:
			continue

		if visual_slot.sprite_frames == null:
			continue

		if _is_switchable_weapon_slot(visual_slot.item_type) and visual_slot.item_type != active_weapon_slot:
			continue

		if melee_attack_active and visual_slot.item_type == ItemData.ItemType.MeleeWeapon:
			continue

		_apply_equipment_animation(visual_slot, animation_name, equipment_state_changed)


func _apply_equipment_animation(visual_slot: EquipmentVisualSlot, requested_animation: String, force_sync: bool = true) -> void:
	if visual_slot == null or visual_slot.sprite_frames == null:
		return

	var target_animation: String = _get_equipment_animation_name(visual_slot.sprite_frames, requested_animation)
	if target_animation == "":
		visual_slot.stop()
		return

	var target_speed_scale: float = _get_current_animation_speed_scale()
	if not force_sync and String(visual_slot.animation) == target_animation and visual_slot.is_playing():
		visual_slot.speed_scale = target_speed_scale
		return

	visual_slot.play(target_animation)
	var target_frame_count: int = visual_slot.sprite_frames.get_frame_count(target_animation)
	if target_frame_count > 0:
		visual_slot.frame = clamp(anim.frame, 0, target_frame_count - 1)
	visual_slot.speed_scale = target_speed_scale


func _get_equipment_animation_name(frames: SpriteFrames, requested_animation: String) -> String:
	if frames == null:
		return ""
	var direct_match: String = _find_equipment_animation_case_insensitive(frames, requested_animation)
	if not direct_match.is_empty():
		return direct_match
	if requested_animation == "Using" and not _find_equipment_animation_case_insensitive(frames, "Action").is_empty():
		return "Action"
	if requested_animation == "Action" and not _find_equipment_animation_case_insensitive(frames, "Using").is_empty():
		return "Using"
	if requested_animation.ends_with("_weapon"):
		var base_idle_animation: String = requested_animation.trim_suffix("_weapon")
		var base_idle_match: String = _find_equipment_animation_case_insensitive(frames, base_idle_animation)
		if not base_idle_match.is_empty():
			return base_idle_match
	if requested_animation.begins_with("Aim_"):
		var fallback_animation: String = "Idle_" + requested_animation.trim_prefix("Aim_")
		var fallback_match: String = _find_equipment_animation_case_insensitive(frames, fallback_animation)
		if not fallback_match.is_empty():
			return fallback_match
	var directional_fallback: String = _find_directional_equipment_animation_fallback(frames, requested_animation)
	if not directional_fallback.is_empty():
		return directional_fallback
	return ""


func _find_equipment_animation_case_insensitive(frames: SpriteFrames, expected_name: String) -> String:
	if frames == null or expected_name.is_empty():
		return ""
	var expected_lower: String = expected_name.to_lower()
	for anim_name_variant: Variant in frames.get_animation_names():
		var anim_name: StringName = anim_name_variant as StringName
		if String(anim_name).to_lower() == expected_lower:
			return String(anim_name)
	return ""


func _find_directional_equipment_animation_fallback(frames: SpriteFrames, requested_animation: String) -> String:
	if frames == null:
		return ""
	var direction: String = ""
	var requested_lower: String = requested_animation.to_lower()
	if requested_lower.ends_with("down"):
		direction = "down"
	elif requested_lower.ends_with("up"):
		direction = "up"
	elif requested_lower.ends_with("left"):
		direction = "left"
	elif requested_lower.ends_with("right"):
		direction = "right"
	if direction.is_empty():
		return ""
	var candidates: Array[String] = [
		"Aim_" + direction,
		"Idle_" + direction,
		direction.capitalize()
	]
	for candidate in candidates:
		var match_name: String = _find_equipment_animation_case_insensitive(frames, candidate)
		if not match_name.is_empty():
			return match_name
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
	if _is_networked_game() and (NetworkManager == null or not NetworkManager.is_server()):
		return
	if vitals_controller != null:
		vitals_controller.take_damage(amount, damage_type, apply_clothing_damage)


func take_damage_from(amount: float, source: Node, hit_context: Dictionary = {}) -> void:
	if _is_networked_game() and (NetworkManager == null or not NetworkManager.is_server()):
		return
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
	if _is_networked_game() and (NetworkManager == null or not NetworkManager.is_server()):
		return
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
	if GameSaveManager != null and GameSaveManager.has_method("change_scene_with_cleanup"):
		GameSaveManager.change_scene_with_cleanup("res://Menu/Menu.tscn")
		return
	get_tree().change_scene_to_file("res://Menu/Menu.tscn")


func _toggle_pause_menu() -> void:
	if get_tree().paused and _pause_menu_root != null and _pause_menu_root.visible:
		_close_pause_menu()
		return
	_open_pause_menu()


func _open_pause_menu() -> void:
	_ensure_pause_menu()
	if _pause_menu_root == null:
		return
	_pause_menu_root.visible = true
	get_tree().paused = true


func _close_pause_menu() -> void:
	get_tree().paused = false
	if _pause_menu_root != null:
		_pause_menu_root.visible = false


func _ensure_pause_menu() -> void:
	if _pause_menu_layer != null and is_instance_valid(_pause_menu_layer):
		return

	_pause_menu_layer = CanvasLayer.new()
	_pause_menu_layer.name = "PauseMenuLayer"
	_pause_menu_layer.layer = 150
	_pause_menu_layer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	get_tree().root.add_child(_pause_menu_layer)

	_pause_menu_root = Control.new()
	_pause_menu_root.name = "PauseMenuRoot"
	_pause_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_menu_root.offset_left = 0.0
	_pause_menu_root.offset_top = 0.0
	_pause_menu_root.offset_right = 0.0
	_pause_menu_root.offset_bottom = 0.0
	_pause_menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_menu_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_pause_menu_layer.add_child(_pause_menu_root)

	var shade := ColorRect.new()
	shade.name = "PauseShade"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.offset_left = 0.0
	shade.offset_top = 0.0
	shade.offset_right = 0.0
	shade.offset_bottom = 0.0
	shade.color = Color(0.03, 0.04, 0.05, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_menu_root.add_child(shade)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 0.0
	center.offset_top = 0.0
	center.offset_right = 0.0
	center.offset_bottom = 0.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_menu_root.add_child(center)

	_pause_menu_panel = PanelContainer.new()
	_pause_menu_panel.name = "Panel"
	_pause_menu_panel.custom_minimum_size = Vector2(320.0, 220.0)
	_pause_menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_pause_menu_panel)

	var vbox := VBoxContainer.new()
	vbox.name = "Buttons"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	_pause_menu_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Пауза"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	vbox.add_child(title)

	_pause_continue_button = Button.new()
	_pause_continue_button.text = "Продолжить"
	_pause_continue_button.custom_minimum_size = Vector2(230.0, 52.0)
	_pause_continue_button.focus_mode = Control.FOCUS_NONE
	_pause_continue_button.pressed.connect(_on_pause_continue_pressed)
	vbox.add_child(_pause_continue_button)

	_pause_main_menu_button = Button.new()
	_pause_main_menu_button.text = "В главное меню"
	_pause_main_menu_button.custom_minimum_size = Vector2(230.0, 52.0)
	_pause_main_menu_button.focus_mode = Control.FOCUS_NONE
	_pause_main_menu_button.pressed.connect(_on_pause_main_menu_pressed)
	vbox.add_child(_pause_main_menu_button)

	_pause_menu_root.visible = false


func _on_pause_continue_pressed() -> void:
	_close_pause_menu()


func _on_pause_main_menu_pressed() -> void:
	_close_pause_menu()
	_go_to_menu(true)


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


func set_debug_invulnerable(enabled: bool) -> void:
	debug_invulnerable = enabled
	if debug_invulnerable and health <= 0.0:
		health = clamp(max_health, 1.0, max_health)
		is_dead = false
		stats_changed.emit()


func set_debug_base_move_speed(value: float) -> void:
	base_move_speed = max(value, 1.0)
	speed = base_move_speed


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
	var carry_multiplier: float = _get_encumbrance_speed_multiplier()
	if is_fractured:
		return stamina_multiplier * stealth_multiplier * carry_multiplier * clamp(fracture_speed_multiplier, 0.0, 1.0)
	return stamina_multiplier * stealth_multiplier * carry_multiplier


func _get_current_animation_speed_scale() -> float:
	var stamina_animation: float = lerp(min_exhausted_animation_multiplier, 1.0, _get_stamina_ratio())
	return base_animation_speed_scale * stamina_animation * _get_stealth_animation_multiplier() * _get_encumbrance_animation_multiplier()


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


func _update_carry_weight_state_if_due(delta: float) -> void:
	_carry_weight_refresh_timer -= delta
	if _carry_weight_refresh_timer > 0.0:
		return
	_carry_weight_refresh_timer = maxf(carry_weight_update_interval_sec, 0.05)
	_update_carry_weight_state()


func _update_carry_weight_state() -> void:
	if InventoryManager == null or not InventoryManager.has_method("get_total_carried_weight"):
		current_carry_weight = 0.0
		current_encumbrance_ratio = 0.0
		_carry_weight_refresh_timer = maxf(carry_weight_update_interval_sec, 0.05)
		return

	current_carry_weight = max(float(InventoryManager.get_total_carried_weight()), 0.0)
	var soft_limit: float = max(carry_weight_soft_limit, 0.0)
	var hard_limit: float = max(carry_weight_hard_limit, soft_limit + 0.01)
	current_encumbrance_ratio = clamp((current_carry_weight - soft_limit) / (hard_limit - soft_limit), 0.0, 1.0)
	_carry_weight_refresh_timer = maxf(carry_weight_update_interval_sec, 0.05)


func _get_encumbrance_speed_multiplier() -> float:
	return lerp(1.0, clamp(overloaded_speed_multiplier, 0.05, 1.0), current_encumbrance_ratio)


func _get_encumbrance_animation_multiplier() -> float:
	return _get_encumbrance_speed_multiplier()


func get_stamina_drain_multiplier() -> float:
	return lerp(1.0, max(overloaded_stamina_drain_multiplier, 1.0), current_encumbrance_ratio)


func get_stamina_recovery_multiplier() -> float:
	return lerp(1.0, clamp(overloaded_stamina_recovery_multiplier, 0.0, 1.0), current_encumbrance_ratio)


func get_encumbrance_noise_multiplier() -> float:
	return lerp(1.0, max(overloaded_noise_multiplier, 1.0), current_encumbrance_ratio)


func get_carry_weight_ratio() -> float:
	var hard_limit: float = max(carry_weight_hard_limit, 0.01)
	return clamp(current_carry_weight / hard_limit, 0.0, 1.0)


func _update_stealth_state() -> void:
	if movement_controller == null:
		return
	var stealth_state: Dictionary = movement_controller.update_stealth_state(stealth_action_name, base_noise_level, stealth_noise_multiplier)
	is_stealth = bool(stealth_state.get("is_stealth", false))
	current_noise_level = float(stealth_state.get("current_noise_level", base_noise_level)) * get_encumbrance_noise_multiplier()


func get_noise_loudness_multiplier() -> float:
	return _get_stealth_noise_multiplier() * get_encumbrance_noise_multiplier()


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


func try_primary_interaction() -> bool:
	if inventory_root != null and "is_inventory_open" in inventory_root and inventory_root.is_inventory_open:
		return true
	if _trigger_primary_interaction():
		return true
	if inventory_root != null and inventory_root.has_method("pickup_first_nearby_item"):
		return bool(inventory_root.pickup_first_nearby_item())
	return false


func try_secondary_interaction() -> bool:
	return _trigger_secondary_interaction()


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


func _is_networked_game() -> bool:
	return multiplayer != null and multiplayer.multiplayer_peer != null


func _is_local_control_enabled() -> bool:
	if not _is_networked_game():
		return true
	return _is_local_network_player()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_submit_input(input_vector: Vector2, input_seq: int) -> void:
	if not _is_networked_game() or NetworkManager == null or not NetworkManager.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	if input_seq <= _net_last_applied_input_seq:
		return
	if _lan_net_debug_enabled:
		_record_server_input_arrival()
	_net_server_last_input_recv_ms = Time.get_ticks_msec()
	_net_input_vector = input_vector.limit_length(1.0)
	_net_last_applied_input_seq = input_seq


@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_submit_state(client_position: Vector2, client_velocity: Vector2, state_seq: int) -> void:
	if not NET_ENABLE_STATE_SYNC:
		return
	if not _is_networked_game() or NetworkManager == null or not NetworkManager.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	if state_seq <= _net_last_applied_state_seq:
		return
	_net_last_applied_state_seq = state_seq
	var now_ms: int = Time.get_ticks_msec()
	var previous_state_recv_ms: int = _net_server_last_state_recv_ms
	_net_server_last_state_recv_ms = now_ms
	if _lan_net_debug_enabled:
		_record_server_state_arrival()

	var clamped_velocity: Vector2 = client_velocity.limit_length(NET_MAX_SPEED)
	var safe_position: Vector2 = client_position
	if _net_server_has_state:
		var delta_pos: Vector2 = safe_position - _net_server_last_state_position
		var max_delta: float = _get_allowed_client_state_delta(previous_state_recv_ms, now_ms)
		if delta_pos.length() > max_delta:
			safe_position = _net_server_last_state_position + delta_pos.normalized() * max_delta
	_net_server_last_state_position = safe_position
	_net_server_last_state_velocity = clamped_velocity
	_net_server_has_state = true


@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_server_sync_state(state_peer_id: int, server_position: Vector2, server_velocity: Vector2, ack_input_seq: int) -> void:
	if not _is_networked_game():
		return
	if NetworkManager == null:
		return
	if not NetworkManager.is_server():
		var sender_id: int = multiplayer.get_remote_sender_id()
		if sender_id != 1:
			return
	if state_peer_id != peer_id:
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _net_last_remote_update_ms < NET_MIN_UPDATE_INTERVAL_MS:
		return
	_net_last_remote_update_ms = now_ms

	var clamped_velocity: Vector2 = server_velocity.limit_length(NET_MAX_SPEED)
	var proposed_delta: Vector2 = server_position - _net_last_remote_position
	if proposed_delta.length() > NET_MAX_POSITION_DELTA_PER_UPDATE:
		server_position = _net_last_remote_position + proposed_delta.normalized() * NET_MAX_POSITION_DELTA_PER_UPDATE

	_net_last_remote_position = server_position
	_net_target_position = server_position
	_net_target_velocity = clamped_velocity
	_push_remote_snapshot(server_position, clamped_velocity)

	if _is_local_network_player():
		_net_last_server_ack_seq = maxi(_net_last_server_ack_seq, ack_input_seq)
		_reconcile_local_authoritative_state(server_position, clamped_velocity)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_sync_player_snapshot(payload: Dictionary) -> void:
	if not _is_networked_game():
		return
	if NetworkManager == null or NetworkManager.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 1:
		return

	var state_peer_id: int = int(payload.get("pid", 0))
	if state_peer_id != peer_id:
		return
	if _lan_net_debug_enabled:
		_record_network_snapshot_arrival()

	var server_time_sec: float = float(payload.get("t", Time.get_ticks_msec())) / 1000.0
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	var measured_offset: float = now_sec - server_time_sec
	if not _net_server_time_offset_initialized:
		_net_server_time_offset_sec = measured_offset
		_net_server_time_offset_initialized = true
	else:
		_net_server_time_offset_sec = lerpf(_net_server_time_offset_sec, measured_offset, 0.08)

	var server_position := Vector2(
		_dequantize_scalar(int(payload.get("px", 0)), NET_SNAPSHOT_POS_SCALE),
		_dequantize_scalar(int(payload.get("py", 0)), NET_SNAPSHOT_POS_SCALE)
	)
	var server_velocity := Vector2(
		_dequantize_scalar(int(payload.get("vx", 0)), NET_SNAPSHOT_VEL_SCALE),
		_dequantize_scalar(int(payload.get("vy", 0)), NET_SNAPSHOT_VEL_SCALE)
	).limit_length(NET_MAX_SPEED)

	var proposed_delta: Vector2 = server_position - _net_last_remote_position
	if proposed_delta.length() > NET_MAX_POSITION_DELTA_PER_UPDATE:
		server_position = _net_last_remote_position + proposed_delta.normalized() * NET_MAX_POSITION_DELTA_PER_UPDATE

	_net_last_remote_position = server_position
	_net_target_position = server_position
	_net_target_velocity = server_velocity
	_push_remote_snapshot(server_position, server_velocity, server_time_sec)

	if _is_local_network_player():
		var ack_input_seq: int = int(payload.get("ack", -1))
		_net_last_server_ack_seq = maxi(_net_last_server_ack_seq, ack_input_seq)
		_reconcile_local_authoritative_state(server_position, server_velocity)

	health = clamp(
		_dequantize_scalar(int(payload.get("hp", _quantize_scalar(health, NET_SNAPSHOT_HEALTH_SCALE))), NET_SNAPSHOT_HEALTH_SCALE),
		0.0,
		max_health
	)
	stats_changed.emit()
	var server_is_dead: bool = bool(payload.get("dead", false))
	if server_is_dead and not is_dead:
		if _is_local_network_player():
			die()
		else:
			is_dead = true

	_net_remote_active_weapon_slot = int(payload.get("aws", _net_remote_active_weapon_slot))
	if not _is_local_network_player():
		var equipment_payload: Variant = payload.get("eq", {})
		if equipment_payload is Dictionary and not (equipment_payload as Dictionary).is_empty():
			var eq := equipment_payload as Dictionary
			_net_remote_equipped_paths = {
				ItemData.ItemType.AR_Weapon: String(eq.get("ar", "")),
				ItemData.ItemType.Pistols: String(eq.get("pi", "")),
				ItemData.ItemType.MeleeWeapon: String(eq.get("me", "")),
				ItemData.ItemType.T_shirts: String(eq.get("ts", "")),
				ItemData.ItemType.Jacket: String(eq.get("ja", "")),
				ItemData.ItemType.HeavyArmour: String(eq.get("ha", "")),
				ItemData.ItemType.Trousers: String(eq.get("tr", "")),
				ItemData.ItemType.Bag: String(eq.get("ba", "")),
				ItemData.ItemType.Cap: String(eq.get("ca", ""))
			}
			if _lan_smoke_net_debug:
				print("[LAN_SMOKE_EQ] peer=%d remote_peer=%d aws=%d ar=%s pi=%s me=%s" % [
					NetworkManager.get_local_peer_id() if NetworkManager != null else 0,
					peer_id,
					_net_remote_active_weapon_slot,
					String(eq.get("ar", "")),
					String(eq.get("pi", "")),
					String(eq.get("me", ""))
				])
			_refresh_equipment_visuals()


func _get_network_input_vector() -> Vector2:
	var mobile_controls_node: Node = get_tree().get_first_node_in_group("mobile_controls")
	if mobile_controls_node != null and mobile_controls_node.has_method("get_move_input_vector"):
		var mobile_vector: Vector2 = mobile_controls_node.call("get_move_input_vector") as Vector2
		# If mobile controls are present, they are the authoritative movement source.
		# Falling back to InputMap introduces jittery zero-vectors on some Android devices.
		return mobile_vector.limit_length(1.0)

	if _has_network_input_actions(NET_INPUT_ACTIONS_PRIMARY):
		return Input.get_vector(
			NET_INPUT_ACTIONS_PRIMARY[0],
			NET_INPUT_ACTIONS_PRIMARY[1],
			NET_INPUT_ACTIONS_PRIMARY[2],
			NET_INPUT_ACTIONS_PRIMARY[3]
		)
	if _has_network_input_actions(NET_INPUT_ACTIONS_FALLBACK):
		return Input.get_vector(
			NET_INPUT_ACTIONS_FALLBACK[0],
			NET_INPUT_ACTIONS_FALLBACK[1],
			NET_INPUT_ACTIONS_FALLBACK[2],
			NET_INPUT_ACTIONS_FALLBACK[3]
		)
	return Vector2.ZERO


func _push_remote_snapshot(server_position: Vector2, server_velocity: Vector2, server_time_sec: float = -1.0) -> void:
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	var snapshot_time_sec: float = server_time_sec if server_time_sec > 0.0 else now_sec
	_net_snapshot_buffer.append({
		"t": snapshot_time_sec,
		"p": server_position,
		"v": server_velocity
	})
	var min_time: float = now_sec - maxf(net_snapshot_max_buffer_sec, 0.10)
	while _net_snapshot_buffer.size() > 2 and float(_net_snapshot_buffer[0].get("t", 0.0)) < min_time:
		_net_snapshot_buffer.remove_at(0)


func _apply_remote_snapshot_interpolation() -> void:
	if _is_local_network_player():
		velocity = _net_target_velocity
		return
	if _net_snapshot_buffer.size() < 2:
		global_position = global_position.lerp(_net_target_position, 0.35)
		velocity = _net_target_velocity
		return

	var render_time: float = float(Time.get_ticks_msec()) / 1000.0 - _net_server_time_offset_sec - clampf(net_snapshot_interp_delay_sec, 0.02, 0.30)
	var a: Dictionary = _net_snapshot_buffer[0]
	var b: Dictionary = _net_snapshot_buffer[1]
	for i in range(_net_snapshot_buffer.size() - 1):
		var left: Dictionary = _net_snapshot_buffer[i]
		var right: Dictionary = _net_snapshot_buffer[i + 1]
		var left_t: float = float(left.get("t", 0.0))
		var right_t: float = float(right.get("t", left_t + 0.001))
		if render_time >= left_t and render_time <= right_t:
			a = left
			b = right
			break
		if render_time > right_t:
			a = right
			b = right

	var at: float = float(a.get("t", 0.0))
	var bt: float = float(b.get("t", at + 0.001))
	var alpha: float = 1.0 if is_equal_approx(bt, at) else clamp((render_time - at) / max(bt - at, 0.0001), 0.0, 1.0)
	var ap: Vector2 = a.get("p", _net_target_position) as Vector2
	var bp: Vector2 = b.get("p", _net_target_position) as Vector2
	var av: Vector2 = a.get("v", _net_target_velocity) as Vector2
	var bv: Vector2 = b.get("v", _net_target_velocity) as Vector2
	global_position = ap.lerp(bp, alpha)
	velocity = av.lerp(bv, alpha)


func _has_network_input_actions(actions: Array[StringName]) -> bool:
	for action_name: StringName in actions:
		if not InputMap.has_action(action_name):
			return false
	return true


func _is_local_network_player() -> bool:
	if not _is_networked_game() or NetworkManager == null:
		return false
	return peer_id == NetworkManager.get_local_peer_id()


func _is_network_peer_still_connected(target_peer_id: int) -> bool:
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return false
	if target_peer_id <= 1:
		return true
	var peers: PackedInt32Array = multiplayer.get_peers()
	return peers.has(target_peer_id)


func _get_ready_client_peers() -> PackedInt32Array:
	var result: PackedInt32Array = []
	if not _is_networked_game() or NetworkManager == null or not NetworkManager.is_server():
		return result
	if NetworkManager.has_method("get_active_client_peers"):
		return NetworkManager.get_active_client_peers()
	return NetworkManager.get_ready_client_peers()


func _broadcast_server_sync_state_interest(
	state_peer_id: int,
	server_position: Vector2,
	server_velocity: Vector2,
	ack_input_seq: int,
	delta: float
) -> void:
	var ready_peers: PackedInt32Array = _get_ready_client_peers()
	if ready_peers.is_empty():
		_net_state_sync_timer_by_peer.clear()
		return

	var alive_keys: Dictionary = {}
	for target_peer_id in ready_peers:
		var target_player := _get_player_node_by_peer_id(target_peer_id)
		var interval_sec: float = NET_STATE_SYNC_INTERVAL_NEAR_SEC
		if target_player != null:
			var distance_to_target: float = global_position.distance_to(target_player.global_position)
			if distance_to_target >= NET_STATE_SYNC_FAR_DISTANCE_PX:
				interval_sec = NET_STATE_SYNC_INTERVAL_FAR_SEC

		var timer_left: float = float(_net_state_sync_timer_by_peer.get(target_peer_id, 0.0)) - delta
		if timer_left <= 0.0:
			rpc_id(target_peer_id, "rpc_server_sync_state", state_peer_id, server_position, server_velocity, ack_input_seq)
			timer_left = interval_sec
		_net_state_sync_timer_by_peer[target_peer_id] = timer_left
		alive_keys[target_peer_id] = true

	for cached_peer_id in _net_state_sync_timer_by_peer.keys():
		if not alive_keys.has(cached_peer_id):
			_net_state_sync_timer_by_peer.erase(cached_peer_id)


func _broadcast_player_snapshot_interest(delta: float) -> void:
	var ready_peers: PackedInt32Array = _get_ready_client_peers()
	if ready_peers.is_empty():
		_net_state_sync_timer_by_peer.clear()
		_net_last_sent_equipment_signature_by_peer.clear()
		return

	var equipment_signature: String = _build_equipment_signature()
	var payload_base: Dictionary = _build_player_snapshot_payload(false)
	var payload_with_equipment: Dictionary = {}
	var alive_keys: Dictionary = {}
	for target_peer_id in ready_peers:
		var target_player := _get_player_node_by_peer_id(target_peer_id)
		var interval_sec: float = NET_STATE_SYNC_INTERVAL_NEAR_SEC
		if target_player != null:
			var distance_to_target: float = global_position.distance_to(target_player.global_position)
			if distance_to_target >= NET_STATE_SYNC_FAR_DISTANCE_PX:
				interval_sec = NET_STATE_SYNC_INTERVAL_FAR_SEC
		var timer_left: float = float(_net_state_sync_timer_by_peer.get(target_peer_id, 0.0)) - delta
		if timer_left <= 0.0:
			var last_signature: String = String(_net_last_sent_equipment_signature_by_peer.get(target_peer_id, ""))
			var include_equipment_for_peer: bool = last_signature != equipment_signature
			if include_equipment_for_peer:
				if payload_with_equipment.is_empty():
					payload_with_equipment = _build_player_snapshot_payload(true)
				rpc_id(target_peer_id, "rpc_sync_player_snapshot", payload_with_equipment)
				_net_last_sent_equipment_signature_by_peer[target_peer_id] = equipment_signature
			else:
				rpc_id(target_peer_id, "rpc_sync_player_snapshot", payload_base)
			timer_left = interval_sec
		_net_state_sync_timer_by_peer[target_peer_id] = timer_left
		alive_keys[target_peer_id] = true

	for cached_peer_id in _net_state_sync_timer_by_peer.keys():
		if not alive_keys.has(cached_peer_id):
			_net_state_sync_timer_by_peer.erase(cached_peer_id)
	for cached_peer_id in _net_last_sent_equipment_signature_by_peer.keys():
		if not alive_keys.has(cached_peer_id):
			_net_last_sent_equipment_signature_by_peer.erase(cached_peer_id)


func _broadcast_server_sync_state(state_peer_id: int, server_position: Vector2, server_velocity: Vector2, ack_input_seq: int) -> void:
	for target_peer_id in _get_ready_client_peers():
		rpc_id(target_peer_id, "rpc_server_sync_state", state_peer_id, server_position, server_velocity, ack_input_seq)


func _broadcast_vitals_sync(state_peer_id: int, server_health: float, server_is_dead: bool) -> void:
	for target_peer_id in _get_ready_client_peers():
		rpc_id(target_peer_id, "rpc_sync_vitals", state_peer_id, server_health, server_is_dead)


func _broadcast_equipment_sync(
	state_peer_id: int,
	active_weapon_slot: int,
	ar_path: String,
	pistol_path: String,
	melee_path: String,
	tshirt_path: String,
	jacket_path: String,
	heavy_path: String,
	trousers_path: String,
	bag_path: String,
	cap_path: String
) -> void:
	for target_peer_id in _get_ready_client_peers():
		rpc_id(
			target_peer_id,
			"rpc_sync_equipment_state",
			state_peer_id,
			active_weapon_slot,
			ar_path,
			pistol_path,
			melee_path,
			tshirt_path,
			jacket_path,
			heavy_path,
			trousers_path,
			bag_path,
			cap_path
		)


func _get_player_node_by_peer_id(target_peer_id: int) -> CharacterBody2D:
	if target_peer_id <= 0:
		return null
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as CharacterBody2D
		if candidate == null or not is_instance_valid(candidate):
			continue
		if int(candidate.get("peer_id")) == target_peer_id:
			return candidate
	return null


func _has_equipment_signature_changed() -> bool:
	var signature: String = _build_equipment_signature()
	if signature == _net_last_sent_equipment_signature:
		return false
	_net_last_sent_equipment_signature = signature
	return true


func _build_equipment_signature() -> String:
	var eq_state: Dictionary = _get_authoritative_equipment_state_for_broadcast()
	var active_weapon_slot: int = int(eq_state.get("aws", ItemData.ItemType.AR_Weapon))
	var ar_path: String = String(eq_state.get("ar", ""))
	var pistol_path: String = String(eq_state.get("pi", ""))
	var melee_path: String = String(eq_state.get("me", ""))
	var tshirt_path: String = String(eq_state.get("ts", ""))
	var jacket_path: String = String(eq_state.get("ja", ""))
	var heavy_path: String = String(eq_state.get("ha", ""))
	var trousers_path: String = String(eq_state.get("tr", ""))
	var bag_path: String = String(eq_state.get("ba", ""))
	var cap_path: String = String(eq_state.get("ca", ""))
	return "%d|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		active_weapon_slot,
		ar_path, pistol_path, melee_path, tshirt_path, jacket_path,
		heavy_path, trousers_path, bag_path, cap_path
	]


func _build_player_snapshot_payload(include_equipment: bool) -> Dictionary:
	var eq_state: Dictionary = _get_authoritative_equipment_state_for_broadcast()
	var payload: Dictionary = {
		"pid": peer_id,
		"t": Time.get_ticks_msec(),
		"px": _quantize_scalar(global_position.x, NET_SNAPSHOT_POS_SCALE),
		"py": _quantize_scalar(global_position.y, NET_SNAPSHOT_POS_SCALE),
		"vx": _quantize_scalar(velocity.x, NET_SNAPSHOT_VEL_SCALE),
		"vy": _quantize_scalar(velocity.y, NET_SNAPSHOT_VEL_SCALE),
		"ack": _net_last_applied_input_seq,
		"hp": _quantize_scalar(health, NET_SNAPSHOT_HEALTH_SCALE),
		"dead": is_dead,
		"aws": int(eq_state.get("aws", ItemData.ItemType.AR_Weapon))
	}
	if include_equipment:
		payload["eq"] = {
			"ar": String(eq_state.get("ar", "")),
			"pi": String(eq_state.get("pi", "")),
			"me": String(eq_state.get("me", "")),
			"ts": String(eq_state.get("ts", "")),
			"ja": String(eq_state.get("ja", "")),
			"ha": String(eq_state.get("ha", "")),
			"tr": String(eq_state.get("tr", "")),
			"ba": String(eq_state.get("ba", "")),
			"ca": String(eq_state.get("ca", ""))
		}
	return payload


func _get_authoritative_equipment_state_for_broadcast() -> Dictionary:
	if _is_networked_game() and NetworkManager != null and NetworkManager.is_server() and not _is_local_network_player() and _net_reported_equipment_initialized:
		return {
			"aws": _net_reported_active_weapon_slot,
			"ar": String(_net_reported_equipped_paths.get(ItemData.ItemType.AR_Weapon, "")),
			"pi": String(_net_reported_equipped_paths.get(ItemData.ItemType.Pistols, "")),
			"me": String(_net_reported_equipped_paths.get(ItemData.ItemType.MeleeWeapon, "")),
			"ts": String(_net_reported_equipped_paths.get(ItemData.ItemType.T_shirts, "")),
			"ja": String(_net_reported_equipped_paths.get(ItemData.ItemType.Jacket, "")),
			"ha": String(_net_reported_equipped_paths.get(ItemData.ItemType.HeavyArmour, "")),
			"tr": String(_net_reported_equipped_paths.get(ItemData.ItemType.Trousers, "")),
			"ba": String(_net_reported_equipped_paths.get(ItemData.ItemType.Bag, "")),
			"ca": String(_net_reported_equipped_paths.get(ItemData.ItemType.Cap, ""))
		}
	return {
		"aws": InventoryManager.get_active_weapon_slot(),
		"ar": _get_equipped_definition_path(ItemData.ItemType.AR_Weapon),
		"pi": _get_equipped_definition_path(ItemData.ItemType.Pistols),
		"me": _get_equipped_definition_path(ItemData.ItemType.MeleeWeapon),
		"ts": _get_equipped_definition_path(ItemData.ItemType.T_shirts),
		"ja": _get_equipped_definition_path(ItemData.ItemType.Jacket),
		"ha": _get_equipped_definition_path(ItemData.ItemType.HeavyArmour),
		"tr": _get_equipped_definition_path(ItemData.ItemType.Trousers),
		"ba": _get_equipped_definition_path(ItemData.ItemType.Bag),
		"ca": _get_equipped_definition_path(ItemData.ItemType.Cap)
	}


func _quantize_scalar(value: float, scale: float) -> int:
	return int(round(value * maxf(scale, 0.0001)))


func _dequantize_scalar(value: int, scale: float) -> float:
	return float(value) / maxf(scale, 0.0001)


func _record_lag_history_sample_if_due(delta: float) -> void:
	_net_lag_history_sample_timer -= delta
	if _net_lag_history_sample_timer > 0.0:
		return
	_net_lag_history_sample_timer = maxf(net_lag_history_sample_interval_sec, 0.005)
	var now_ms: int = Time.get_ticks_msec()
	_net_lag_history_samples.append({
		"t": now_ms,
		"p": global_position
	})
	var min_allowed_ms: int = now_ms - int(maxf(net_lag_history_duration_sec, 0.20) * 1000.0)
	while _net_lag_history_samples.size() > 2 and int(_net_lag_history_samples[0].get("t", 0)) < min_allowed_ms:
		_net_lag_history_samples.remove_at(0)


func get_lag_compensated_position_at_ms(server_time_ms: int) -> Dictionary:
	if _net_lag_history_samples.is_empty():
		return {"ok": false, "position": global_position}
	if _net_lag_history_samples.size() == 1:
		return {"ok": true, "position": _net_lag_history_samples[0].get("p", global_position)}

	var first: Dictionary = _net_lag_history_samples[0]
	var last: Dictionary = _net_lag_history_samples[_net_lag_history_samples.size() - 1]
	var first_t: int = int(first.get("t", server_time_ms))
	var last_t: int = int(last.get("t", server_time_ms))
	var clamped_time: int = clampi(server_time_ms, first_t, last_t)
	var a: Dictionary = first
	var b: Dictionary = last
	for i in range(_net_lag_history_samples.size() - 1):
		var left: Dictionary = _net_lag_history_samples[i]
		var right: Dictionary = _net_lag_history_samples[i + 1]
		var left_t: int = int(left.get("t", clamped_time))
		var right_t: int = int(right.get("t", left_t))
		if clamped_time >= left_t and clamped_time <= right_t:
			a = left
			b = right
			break

	var at: int = int(a.get("t", clamped_time))
	var bt: int = int(b.get("t", at))
	var ap: Vector2 = a.get("p", global_position) as Vector2
	var bp: Vector2 = b.get("p", ap) as Vector2
	if bt <= at:
		return {"ok": true, "position": ap}
	var alpha: float = clamp(float(clamped_time - at) / float(bt - at), 0.0, 1.0)
	return {"ok": true, "position": ap.lerp(bp, alpha)}


func _sync_network_equipment_state_if_needed() -> void:
	if not _is_networked_game() or NetworkManager == null or not NetworkManager.is_server():
		return
	var active_weapon_slot: int = InventoryManager.get_active_weapon_slot()
	var ar_path: String = _get_equipped_definition_path(ItemData.ItemType.AR_Weapon)
	var pistol_path: String = _get_equipped_definition_path(ItemData.ItemType.Pistols)
	var melee_path: String = _get_equipped_definition_path(ItemData.ItemType.MeleeWeapon)
	var tshirt_path: String = _get_equipped_definition_path(ItemData.ItemType.T_shirts)
	var jacket_path: String = _get_equipped_definition_path(ItemData.ItemType.Jacket)
	var heavy_path: String = _get_equipped_definition_path(ItemData.ItemType.HeavyArmour)
	var trousers_path: String = _get_equipped_definition_path(ItemData.ItemType.Trousers)
	var bag_path: String = _get_equipped_definition_path(ItemData.ItemType.Bag)
	var cap_path: String = _get_equipped_definition_path(ItemData.ItemType.Cap)
	var signature: String = "%d|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		active_weapon_slot,
		ar_path, pistol_path, melee_path, tshirt_path, jacket_path,
		heavy_path, trousers_path, bag_path, cap_path
	]
	if signature == _net_last_sent_equipment_signature:
		return
	_net_last_sent_equipment_signature = signature
	_broadcast_equipment_sync(
		peer_id,
		active_weapon_slot,
		ar_path,
		pistol_path,
		melee_path,
		tshirt_path,
		jacket_path,
		heavy_path,
		trousers_path,
		bag_path,
		cap_path
	)


func _get_equipped_definition_path(slot_type: int) -> String:
	var item: ItemData = InventoryManager.get_equipped(slot_type)
	if item == null:
		return ""
	var definition: ItemData = item.get_definition() if item.has_method("get_definition") else item
	if definition == null:
		return ""
	return definition.resource_path


func _has_cli_flag(flag_name: String) -> bool:
	for raw_arg_variant: Variant in OS.get_cmdline_user_args():
		var raw_arg: String = String(raw_arg_variant).strip_edges()
		if raw_arg == "--%s" % flag_name:
			return true
		if raw_arg.begins_with("--%s=" % flag_name):
			var value: String = raw_arg.trim_prefix("--%s=" % flag_name).strip_edges().to_lower()
			return value in ["1", "true", "yes", "on"]
	return false


func _record_network_snapshot_arrival() -> void:
	var now_ms: int = Time.get_ticks_msec()
	_net_debug_snapshot_count += 1
	if _net_debug_last_snapshot_recv_ms > 0:
		var gap_ms: float = float(max(now_ms - _net_debug_last_snapshot_recv_ms, 0))
		_net_debug_snapshot_gap_sum_ms += gap_ms
		_net_debug_snapshot_gap_max_ms = maxf(_net_debug_snapshot_gap_max_ms, gap_ms)
	_net_debug_last_snapshot_recv_ms = now_ms


func _accumulate_network_correction(correction_px: float, is_snap: bool) -> void:
	_net_debug_correction_count += 1
	_net_debug_correction_sum_px += correction_px
	_net_debug_correction_max_px = maxf(_net_debug_correction_max_px, correction_px)
	if is_snap:
		_net_debug_snap_count += 1


func _emit_network_debug_metrics() -> void:
	if not _is_networked_game():
		return
	var role: String = "host" if NetworkManager != null and NetworkManager.is_server() else "client"
	var is_host_role: bool = role == "host"
	var is_local_actor: bool = _is_local_network_player()
	var local_peer: int = NetworkManager.get_local_peer_id() if NetworkManager != null else peer_id
	var rtt_ms: float = NetworkManager.get_rtt_ms() if NetworkManager != null and NetworkManager.has_method("get_rtt_ms") else -1.0
	var loss_percent: float = NetworkManager.get_packet_loss_percent() if NetworkManager != null and NetworkManager.has_method("get_packet_loss_percent") else 0.0
	var avg_corr_px: float = _net_debug_correction_sum_px / float(_net_debug_correction_count) if _net_debug_correction_count > 0 else 0.0
	var avg_snap_gap_ms: float = _net_debug_snapshot_gap_sum_ms / float(max(_net_debug_snapshot_count - 1, 1))
	var target_error_px: float = 0.0 if is_host_role else global_position.distance_to(_net_target_position)
	var pending_inputs: int = maxi(_net_input_seq - _net_last_server_ack_seq - 1, 0) if is_local_actor else 0
	var server_input_rate: float = float(_net_debug_server_input_count)
	var server_input_gap_avg_ms: float = _net_debug_server_input_gap_sum_ms / float(max(_net_debug_server_input_count - 1, 1))
	var server_state_rate: float = float(_net_debug_server_state_count)
	var server_state_gap_avg_ms: float = _net_debug_server_state_gap_sum_ms / float(max(_net_debug_server_state_count - 1, 1))
	var server_state_age_ms: int = Time.get_ticks_msec() - _net_server_last_state_recv_ms if _net_server_has_state else -1
	var using_state_sync: bool = (not is_local_actor) and _has_recent_client_state()
	print("[LAN_NET_DEBUG] role=%s actor_peer=%d local_peer=%d is_local_actor=%s rtt=%.1fms loss=%.1f%% target_err=%.2f corr_avg=%.2f corr_max=%.2f snaps=%d snapsrcv=%d snap_gap_avg=%.1fms snap_gap_max=%.1fms pending_inputs=%d input_rate=%.0f/s input_gap_avg=%.1fms input_gap_max=%.1fms state_sync=%s state_rate=%.0f/s state_gap_avg=%.1fms state_gap_max=%.1fms state_age=%dms server_speed=%.1f" % [
		role,
		peer_id,
		local_peer,
		str(is_local_actor),
		rtt_ms,
		loss_percent,
		target_error_px,
		avg_corr_px,
		_net_debug_correction_max_px,
		_net_debug_snap_count,
		_net_debug_snapshot_count,
		avg_snap_gap_ms,
		_net_debug_snapshot_gap_max_ms,
		pending_inputs,
		server_input_rate,
		server_input_gap_avg_ms,
		_net_debug_server_input_gap_max_ms,
		str(using_state_sync),
		server_state_rate,
		server_state_gap_avg_ms,
		_net_debug_server_state_gap_max_ms,
		server_state_age_ms,
		velocity.length()
	])
	_net_debug_correction_count = 0
	_net_debug_correction_sum_px = 0.0
	_net_debug_correction_max_px = 0.0
	_net_debug_snap_count = 0
	_net_debug_snapshot_count = 0
	_net_debug_snapshot_gap_sum_ms = 0.0
	_net_debug_snapshot_gap_max_ms = 0.0
	_net_debug_server_input_count = 0
	_net_debug_server_input_gap_sum_ms = 0.0
	_net_debug_server_input_gap_max_ms = 0.0
	_net_debug_server_state_count = 0
	_net_debug_server_state_gap_sum_ms = 0.0
	_net_debug_server_state_gap_max_ms = 0.0


func _record_server_input_arrival() -> void:
	var now_ms: int = Time.get_ticks_msec()
	_net_debug_server_input_count += 1
	if _net_debug_server_last_input_recv_ms > 0:
		var gap_ms: float = float(max(now_ms - _net_debug_server_last_input_recv_ms, 0))
		_net_debug_server_input_gap_sum_ms += gap_ms
		_net_debug_server_input_gap_max_ms = maxf(_net_debug_server_input_gap_max_ms, gap_ms)
	_net_debug_server_last_input_recv_ms = now_ms


func _record_server_state_arrival() -> void:
	var now_ms: int = Time.get_ticks_msec()
	_net_debug_server_state_count += 1
	if _net_debug_server_last_state_recv_ms > 0:
		var gap_ms: float = float(max(now_ms - _net_debug_server_last_state_recv_ms, 0))
		_net_debug_server_state_gap_sum_ms += gap_ms
		_net_debug_server_state_gap_max_ms = maxf(_net_debug_server_state_gap_max_ms, gap_ms)
	_net_debug_server_last_state_recv_ms = now_ms


func _has_recent_client_state() -> bool:
	if not _net_server_has_state:
		return false
	var age_ms: int = Time.get_ticks_msec() - _net_server_last_state_recv_ms
	return age_ms <= NET_SERVER_STATE_STALE_TIMEOUT_MS


func _has_usable_client_state() -> bool:
	if not _net_server_has_state:
		return false
	var age_ms: int = Time.get_ticks_msec() - _net_server_last_state_recv_ms
	return age_ms <= NET_SERVER_STATE_HARD_TIMEOUT_MS


func _get_allowed_client_state_delta(previous_recv_ms: int, now_ms: int) -> float:
	if previous_recv_ms <= 0 or now_ms <= previous_recv_ms:
		return NET_SERVER_STATE_MAX_DELTA_MARGIN_PX
	var elapsed_sec: float = clampf(
		float(now_ms - previous_recv_ms) / 1000.0,
		0.0,
		NET_SERVER_STATE_MAX_ELAPSED_SEC
	)
	var max_expected_speed: float = maxf(base_move_speed * _get_current_speed_multiplier(), 1.0)
	var allowed_delta: float = max_expected_speed * elapsed_sec + NET_SERVER_STATE_MAX_DELTA_MARGIN_PX
	return clampf(allowed_delta, NET_SERVER_STATE_MAX_DELTA_MARGIN_PX, NET_SERVER_STATE_MAX_DELTA_PER_UPDATE)


func _reconcile_local_authoritative_state(server_position: Vector2, server_velocity: Vector2) -> void:
	var correction: Vector2 = server_position - global_position
	var correction_px: float = correction.length()
	var should_hard_snap: bool = correction_px > NET_RECONCILE_HARD_SNAP_DISTANCE
	if _lan_net_debug_enabled:
		_accumulate_network_correction(correction_px, should_hard_snap)
	if correction_px <= NET_RECONCILE_SOFT_DEADZONE:
		return
	if should_hard_snap:
		global_position = server_position
		velocity = server_velocity
		return
	var blend_alpha: float = clampf(NET_RECONCILE_SOFT_BLEND_ALPHA, 0.01, 1.0)
	global_position += correction * blend_alpha
	velocity = velocity.lerp(server_velocity, clampf(NET_RECONCILE_VELOCITY_BLEND_ALPHA, 0.0, 1.0))


func _apply_server_received_state() -> void:
	var state_age_ms: int = Time.get_ticks_msec() - _net_server_last_state_recv_ms
	if state_age_ms > NET_SERVER_STATE_HARD_TIMEOUT_MS:
		velocity = velocity.lerp(Vector2.ZERO, 0.35)
		if velocity.length() <= 0.01:
			velocity = Vector2.ZERO
			idle()
		else:
			update_move_animation(velocity.normalized())
		return
	var target_position: Vector2 = _net_server_last_state_position
	if state_age_ms > 0:
		var extrapolation_sec: float = minf(float(state_age_ms) / 1000.0, NET_SERVER_STATE_EXTRAPOLATION_MAX_SEC)
		target_position += _net_server_last_state_velocity * extrapolation_sec
	var clamped_delta: Vector2 = target_position - global_position
	if clamped_delta.length() > NET_SERVER_STATE_MAX_DELTA_PER_UPDATE:
		target_position = global_position + clamped_delta.normalized() * NET_SERVER_STATE_MAX_DELTA_PER_UPDATE
	global_position = global_position.lerp(target_position, NET_SERVER_STATE_POSITION_BLEND)
	velocity = _net_server_last_state_velocity
	if state_age_ms > NET_SERVER_STATE_STALE_TIMEOUT_MS:
		velocity = velocity.lerp(Vector2.ZERO, 0.20)
	if velocity.length() <= 0.01:
		idle()
	else:
		update_move_animation(velocity.normalized())


@rpc("any_peer", "reliable")
func rpc_sync_equipment_state(
	state_peer_id: int,
	active_weapon_slot: int,
	ar_path: String,
	pistol_path: String,
	melee_path: String,
	tshirt_path: String,
	jacket_path: String,
	heavy_path: String,
	trousers_path: String,
	bag_path: String,
	cap_path: String
) -> void:
	if not _is_networked_game():
		return
	if NetworkManager == null:
		return
	if NetworkManager.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 1:
		return
	if state_peer_id != peer_id:
		return
	_net_remote_active_weapon_slot = active_weapon_slot
	_net_remote_equipped_paths = {
		ItemData.ItemType.AR_Weapon: ar_path,
		ItemData.ItemType.Pistols: pistol_path,
		ItemData.ItemType.MeleeWeapon: melee_path,
		ItemData.ItemType.T_shirts: tshirt_path,
		ItemData.ItemType.Jacket: jacket_path,
		ItemData.ItemType.HeavyArmour: heavy_path,
		ItemData.ItemType.Trousers: trousers_path,
		ItemData.ItemType.Bag: bag_path,
		ItemData.ItemType.Cap: cap_path
	}
	_refresh_equipment_visuals()


func _setup_equipment_synchronizer() -> void:
	var synchronizer: MultiplayerSynchronizer = get_node_or_null("EquipmentSynchronizer") as MultiplayerSynchronizer
	if synchronizer == null:
		return
	synchronizer.root_path = NodePath("..")
	var config: SceneReplicationConfig = SceneReplicationConfig.new()
	var properties: Array[NodePath] = [
		NodePath(":net_eq_active_weapon_slot"),
		NodePath(":net_eq_ar_path"),
		NodePath(":net_eq_pistol_path"),
		NodePath(":net_eq_melee_path"),
		NodePath(":net_eq_tshirt_path"),
		NodePath(":net_eq_jacket_path"),
		NodePath(":net_eq_heavy_path"),
		NodePath(":net_eq_trousers_path"),
		NodePath(":net_eq_bag_path"),
		NodePath(":net_eq_cap_path")
	]
	for property_path in properties:
		config.add_property(property_path)
		config.property_set_replication_mode(property_path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	synchronizer.replication_config = config


func _publish_local_equipment_state_to_replication() -> void:
	if not _is_networked_game() or not _is_local_network_player():
		return
	net_eq_active_weapon_slot = InventoryManager.get_active_weapon_slot()
	net_eq_ar_path = _get_equipped_definition_path(ItemData.ItemType.AR_Weapon)
	net_eq_pistol_path = _get_equipped_definition_path(ItemData.ItemType.Pistols)
	net_eq_melee_path = _get_equipped_definition_path(ItemData.ItemType.MeleeWeapon)
	net_eq_tshirt_path = _get_equipped_definition_path(ItemData.ItemType.T_shirts)
	net_eq_jacket_path = _get_equipped_definition_path(ItemData.ItemType.Jacket)
	net_eq_heavy_path = _get_equipped_definition_path(ItemData.ItemType.HeavyArmour)
	net_eq_trousers_path = _get_equipped_definition_path(ItemData.ItemType.Trousers)
	net_eq_bag_path = _get_equipped_definition_path(ItemData.ItemType.Bag)
	net_eq_cap_path = _get_equipped_definition_path(ItemData.ItemType.Cap)


func _on_replicated_equipment_changed() -> void:
	_net_remote_active_weapon_slot = net_eq_active_weapon_slot
	_net_remote_equipped_paths = {
		ItemData.ItemType.AR_Weapon: net_eq_ar_path,
		ItemData.ItemType.Pistols: net_eq_pistol_path,
		ItemData.ItemType.MeleeWeapon: net_eq_melee_path,
		ItemData.ItemType.T_shirts: net_eq_tshirt_path,
		ItemData.ItemType.Jacket: net_eq_jacket_path,
		ItemData.ItemType.HeavyArmour: net_eq_heavy_path,
		ItemData.ItemType.Trousers: net_eq_trousers_path,
		ItemData.ItemType.Bag: net_eq_bag_path,
		ItemData.ItemType.Cap: net_eq_cap_path
	}
	if _is_networked_game() and not _is_local_network_player():
		call_deferred("_refresh_equipment_visuals")


func _apply_remote_equipment_visuals() -> void:
	for visual_slot in equipment_visual_slots:
		var path: String = String(_net_remote_equipped_paths.get(visual_slot.item_type, ""))
		var item: ItemData = _load_item_definition_for_path(path)
		if item == null or item.equipped_frames == null:
			visual_slot.sprite_frames = null
			visual_slot.visible = false
			continue
		if _is_switchable_weapon_slot(visual_slot.item_type) and visual_slot.item_type != _net_remote_active_weapon_slot:
			visual_slot.sprite_frames = item.equipped_frames
			visual_slot.visible = false
			continue
		visual_slot.sprite_frames = item.equipped_frames
		visual_slot.visible = true
		_apply_equipment_animation(visual_slot, String(anim.animation))


func _load_item_definition_for_path(path: String) -> ItemData:
	if path.is_empty():
		return null
	if _net_item_definition_cache.has(path):
		return _net_item_definition_cache[path]
	var resource: Resource = load(path)
	if resource == null or not (resource is ItemData):
		return null
	var item: ItemData = resource as ItemData
	_net_item_definition_cache[path] = item
	return item


func _apply_network_movement(delta: float, input_vector: Vector2) -> void:
	var normalized_input: Vector2 = input_vector.limit_length(1.0)
	var move_speed: float = base_move_speed * _get_current_speed_multiplier()
	velocity = normalized_input * move_speed
	move_and_slide()
	if normalized_input == Vector2.ZERO:
		idle()
	else:
		update_move_animation(normalized_input)
	_update_walk_snow_sfx(normalized_input, delta)


func _refresh_non_blocking_collision_exceptions() -> void:
	if get_tree() == null:
		return
	for peer_variant: Variant in get_tree().get_nodes_in_group("player"):
		var peer_node: Node = peer_variant as Node
		if peer_node == null or not is_instance_valid(peer_node) or peer_node == self:
			continue
		if peer_node is PhysicsBody2D:
			add_collision_exception_with(peer_node as PhysicsBody2D)
	for enemy_variant: Variant in get_tree().get_nodes_in_group("enemy"):
		var enemy_node: Node = enemy_variant as Node
		if enemy_node == null or not is_instance_valid(enemy_node):
			continue
		if enemy_node is PhysicsBody2D:
			add_collision_exception_with(enemy_node as PhysicsBody2D)


@rpc("any_peer", "unreliable")
func rpc_sync_vitals(state_peer_id: int, server_health: float, server_is_dead: bool) -> void:
	if not _is_networked_game():
		return
	if state_peer_id != peer_id:
		return
	if NetworkManager == null:
		return
	if not NetworkManager.is_server():
		var sender_id: int = multiplayer.get_remote_sender_id()
		if sender_id != 1:
			return
	health = clamp(server_health, 0.0, max_health)
	stats_changed.emit()
	if server_is_dead and not is_dead:
		if _is_local_network_player():
			die()
		else:
			is_dead = true


func _enable_network_updates_after_spawn_sync() -> void:
	await get_tree().create_timer(0.08).timeout
	_net_can_send_updates = true
	_publish_local_equipment_state_to_replication()


func _push_local_equipment_state_to_server() -> void:
	if not _is_networked_game() or NetworkManager == null:
		return
	if NetworkManager.is_server():
		return
	if not _is_local_network_player():
		return
	var payload: Dictionary = {
		"aws": InventoryManager.get_active_weapon_slot(),
		"ar": _get_equipped_definition_path(ItemData.ItemType.AR_Weapon),
		"pi": _get_equipped_definition_path(ItemData.ItemType.Pistols),
		"me": _get_equipped_definition_path(ItemData.ItemType.MeleeWeapon),
		"ts": _get_equipped_definition_path(ItemData.ItemType.T_shirts),
		"ja": _get_equipped_definition_path(ItemData.ItemType.Jacket),
		"ha": _get_equipped_definition_path(ItemData.ItemType.HeavyArmour),
		"tr": _get_equipped_definition_path(ItemData.ItemType.Trousers),
		"ba": _get_equipped_definition_path(ItemData.ItemType.Bag),
		"ca": _get_equipped_definition_path(ItemData.ItemType.Cap)
	}
	rpc_id(1, "rpc_submit_equipment_state", payload)


@rpc("any_peer", "reliable")
func rpc_submit_equipment_state(payload: Dictionary) -> void:
	if not _is_networked_game() or NetworkManager == null or not NetworkManager.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	_net_reported_active_weapon_slot = int(payload.get("aws", ItemData.ItemType.AR_Weapon))
	_net_reported_equipped_paths = {
		ItemData.ItemType.AR_Weapon: String(payload.get("ar", "")),
		ItemData.ItemType.Pistols: String(payload.get("pi", "")),
		ItemData.ItemType.MeleeWeapon: String(payload.get("me", "")),
		ItemData.ItemType.T_shirts: String(payload.get("ts", "")),
		ItemData.ItemType.Jacket: String(payload.get("ja", "")),
		ItemData.ItemType.HeavyArmour: String(payload.get("ha", "")),
		ItemData.ItemType.Trousers: String(payload.get("tr", "")),
		ItemData.ItemType.Bag: String(payload.get("ba", "")),
		ItemData.ItemType.Cap: String(payload.get("ca", ""))
	}
	_net_reported_equipment_initialized = true
