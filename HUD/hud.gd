extends CanvasLayer

@export var player_path: NodePath
@export_range(0, 23, 1) var start_hour: int = 8
@export_range(0, 59, 1) var start_minute: int = 0
@export_range(0.05, 60.0, 0.05) var game_minutes_per_real_second: float = 1.0
@export var randomize_start_time_on_new_game: bool = true
@export_range(0, 8, 1) var clock_symbol_gap_px: int = 1
@export_range(0.5, 4.0, 0.1) var clock_symbol_scale: float = 1
@export_range(-50.0, 50.0, 0.5) var night_temperature_celsius: float = -24.0
@export_range(-50.0, 50.0, 0.5) var morning_temperature_celsius: float = -18.0
@export_range(-50.0, 50.0, 0.5) var day_temperature_celsius: float = -8.0
@export_range(-50.0, 50.0, 0.5) var evening_temperature_celsius: float = -14.0
@export_range(-50.0, 50.0, 0.5) var temperature_bar_min_celsius: float = -35.0
@export_range(-50.0, 50.0, 0.5) var temperature_bar_max_celsius: float = 10.0

var player: Node = null

@onready var health_bar: TextureProgressBar = $HealthBar
@onready var temperature_bar: TextureProgressBar = $TemeratureBar
@onready var water_bar: TextureProgressBar = $WaterBar
@onready var food_bar: TextureProgressBar = $FoodBar
@onready var stamina_bar: TextureProgressBar = $StaminaBar
@onready var clock_time_label: Label = $HUDTexture/ClockTimeLabel
@onready var hud_texture: TextureRect = $HUDTexture
@onready var bleeding_icon: Sprite2D = $HUDTexture/Stats/Bleeding
@onready var fracture_icon: Sprite2D = $HUDTexture/Stats/Fracture
@onready var disease_icon: Sprite2D = $HUDTexture/Stats/Disease
@onready var regeneration_icon: Sprite2D = $HUDTexture/Stats/Regeneration

const STATUS_REGENERATION: StringName = &"regeneration"
const STATUS_BLEEDING: StringName = &"bleeding"
const STATUS_FRACTURE: StringName = &"fracture"
const STATUS_DISEASE: StringName = &"disease"
const STATUS_ORDER: Array[StringName] = [
	STATUS_REGENERATION,
	STATUS_BLEEDING,
	STATUS_FRACTURE,
	STATUS_DISEASE
]
const STATUS_ANCHOR_POSITION: Vector2 = Vector2(14.0, 7.0)
const STATUS_FADE_IN_SEC: float = 0.45
const STATUS_FADE_OUT_SEC: float = 0.55
const STATUS_STACK_GAP: float = 19.0
const STATUS_LAYOUT_LERP_SPEED: float = 12.0
const STATUS_WOBBLE_INTERVAL_SEC: float = 5.0
const STATUS_WOBBLE_DURATION_SEC: float = 0.9
const STATUS_WOBBLE_REPETITIONS: float = 3.0
const STATUS_WOBBLE_AMPLITUDE: float = 2.5

const MINUTES_PER_DAY: int = 24 * 60
const SAVE_KEY: String = "hud_game_clock"
const CLOCK_GLYPH_PATHS: Dictionary = {
	"0": "res://Assets/Misc/Alphabet&Numbers/zero.png",
	"1": "res://Assets/Misc/Alphabet&Numbers/one.png",
	"2": "res://Assets/Misc/Alphabet&Numbers/two.png",
	"3": "res://Assets/Misc/Alphabet&Numbers/three.png",
	"4": "res://Assets/Misc/Alphabet&Numbers/four.png",
	"5": "res://Assets/Misc/Alphabet&Numbers/five.png",
	"6": "res://Assets/Misc/Alphabet&Numbers/six.png",
	"7": "res://Assets/Misc/Alphabet&Numbers/seven.png",
	"8": "res://Assets/Misc/Alphabet&Numbers/eight.png",
	"9": "res://Assets/Misc/Alphabet&Numbers/nine.png",
	":": "res://Assets/Misc/Alphabet&Numbers/colon.png"
}
const CLOCK_LAYOUT: String = "00:00"

var game_time_minutes: float = 0.0
var game_time_total_minutes: float = 0.0
var displayed_game_minute: int = -1
var displayed_temperature_value: int = -1
var status_icon_states: Dictionary = {}
var status_icon_base_position: Vector2 = Vector2.ZERO
var debug_forced_statuses: Dictionary = {}
var _clock_glyph_textures: Dictionary = {}
var _clock_glyph_slots: Array[TextureRect] = []
var _clock_glyph_container: HBoxContainer = null
var _clock_glyphs_ready: bool = false


func _ready() -> void:
	_setup_clock_glyphs()
	add_to_group("hud")
	add_to_group("game_clock")
	game_time_total_minutes = float(_resolve_start_time_minutes())
	game_time_minutes = _normalize_time_minutes_float(game_time_total_minutes)
	_update_clock_label(true)
	_update_temperature_bar(true)
	_setup_status_icons()
	if not bind_player(_resolve_player_node()):
		push_error("HUD: player not found (player_path/group 'player').")


func bind_player(new_player: Node) -> bool:
	if player != null and is_instance_valid(player):
		if player.has_signal("stats_changed") and player.stats_changed.is_connected(update_stats):
			player.stats_changed.disconnect(update_stats)
		if player.has_signal("status_effects_changed") and player.status_effects_changed.is_connected(update_status_effects):
			player.status_effects_changed.disconnect(update_status_effects)

	player = new_player
	if player == null or not is_instance_valid(player):
		return false
	if player.is_inside_tree() and is_inside_tree():
		player_path = get_path_to(player)
	if player.has_signal("stats_changed") and not player.stats_changed.is_connected(update_stats):
		player.stats_changed.connect(update_stats)
	if player.has_signal("status_effects_changed") and not player.status_effects_changed.is_connected(update_status_effects):
		player.status_effects_changed.connect(update_status_effects)
	update_stats()
	update_status_effects()
	return true


func _process(delta: float) -> void:
	_update_game_clock(delta)
	_update_status_icon_motion(delta)


func update_stats() -> void:
	if player == null:
		return
	update_health()
	update_water()
	update_food()
	update_stamina()
	update_status_effects()


func update_health() -> void:
	health_bar.max_value = player.max_health
	health_bar.value = player.health


func update_water() -> void:
	water_bar.max_value = player.max_water
	water_bar.value = player.water


func update_food() -> void:
	food_bar.max_value = player.max_food
	food_bar.value = player.food


func update_stamina() -> void:
	stamina_bar.max_value = player.max_stamina
	stamina_bar.value = player.stamina


func update_status_effects() -> void:
	if player == null:
		return

	_set_status_icon_active(STATUS_REGENERATION, _is_status_forced_active(STATUS_REGENERATION) or (player.has_method("has_passive_regeneration") and player.has_passive_regeneration()))
	_set_status_icon_active(STATUS_BLEEDING, _is_status_forced_active(STATUS_BLEEDING) or bool(player.is_bleeding))
	_set_status_icon_active(STATUS_FRACTURE, _is_status_forced_active(STATUS_FRACTURE) or ("is_fractured" in player and player.is_fractured))
	_set_status_icon_active(STATUS_DISEASE, _is_status_forced_active(STATUS_DISEASE) or ("is_diseased" in player and player.is_diseased))
	_update_status_icon_stack()


func _setup_status_icons() -> void:
	status_icon_base_position = STATUS_ANCHOR_POSITION
	status_icon_states = {
		STATUS_REGENERATION: _create_status_icon_state(regeneration_icon),
		STATUS_BLEEDING: _create_status_icon_state(bleeding_icon),
		STATUS_FRACTURE: _create_status_icon_state(fracture_icon),
		STATUS_DISEASE: _create_status_icon_state(disease_icon)
	}

	for status_name in STATUS_ORDER:
		var state: Dictionary = status_icon_states[status_name]
		var icon: Sprite2D = state.get("icon", null) as Sprite2D
		if icon == null:
			continue
		icon.visible = false
		icon.modulate.a = 0.0
		icon.z_index = 10
		icon.position = status_icon_base_position


func _create_status_icon_state(icon: Sprite2D) -> Dictionary:
	return {
		"icon": icon,
		"target_active": false,
		"alpha": 0.0,
		"stack_index": 0,
		"base_position": status_icon_base_position,
		"wobble_wait": STATUS_WOBBLE_INTERVAL_SEC,
		"wobble_time": STATUS_WOBBLE_DURATION_SEC
	}


func _set_status_icon_active(status_name: StringName, active: bool) -> void:
	if not status_icon_states.has(status_name):
		return

	var state: Dictionary = status_icon_states[status_name]
	var was_active: bool = bool(state.get("target_active", false))
	if was_active == active:
		return

	state["target_active"] = active
	if active:
		state["wobble_wait"] = STATUS_WOBBLE_INTERVAL_SEC
		state["wobble_time"] = STATUS_WOBBLE_DURATION_SEC
		var icon: Sprite2D = state.get("icon", null) as Sprite2D
		if icon != null:
			icon.visible = true
	status_icon_states[status_name] = state


func set_debug_status_override(status_name: StringName, enabled: bool) -> void:
	if enabled:
		debug_forced_statuses[status_name] = true
	else:
		debug_forced_statuses.erase(status_name)
	update_status_effects()


func _is_status_forced_active(status_name: StringName) -> bool:
	return bool(debug_forced_statuses.get(status_name, false))


func _update_status_icon_stack() -> void:
	var stack_index: int = 0
	for status_name in STATUS_ORDER:
		var state: Dictionary = status_icon_states[status_name]
		if bool(state.get("target_active", false)) or float(state.get("alpha", 0.0)) > 0.0:
			state["stack_index"] = stack_index
			state["base_position"] = status_icon_base_position + Vector2(0.0, STATUS_STACK_GAP * stack_index)
			stack_index += 1
			status_icon_states[status_name] = state


func _update_status_icon_motion(delta: float) -> void:
	if status_icon_states.is_empty():
		return

	_update_status_icon_stack()
	for status_name in STATUS_ORDER:
		var state: Dictionary = status_icon_states[status_name]
		var icon: Sprite2D = state.get("icon", null) as Sprite2D
		if icon == null:
			continue

		var target_active: bool = bool(state.get("target_active", false))
		var alpha: float = float(state.get("alpha", 0.0))
		if target_active:
			alpha = minf(alpha + delta / STATUS_FADE_IN_SEC, 1.0)
		else:
			alpha = maxf(alpha - delta / STATUS_FADE_OUT_SEC, 0.0)

		state["alpha"] = alpha
		icon.modulate.a = alpha
		icon.visible = alpha > 0.001
		if not icon.visible:
			icon.position = Vector2(state.get("base_position", status_icon_base_position))
			status_icon_states[status_name] = state
			continue

		var base_position := Vector2(state.get("base_position", status_icon_base_position))
		var wobble_offset: float = 0.0
		if target_active:
			var wobble_wait: float = float(state.get("wobble_wait", STATUS_WOBBLE_INTERVAL_SEC))
			var wobble_time: float = float(state.get("wobble_time", STATUS_WOBBLE_DURATION_SEC))
			if wobble_time < STATUS_WOBBLE_DURATION_SEC:
				wobble_time = minf(wobble_time + delta, STATUS_WOBBLE_DURATION_SEC)
				var progress: float = clamp(wobble_time / STATUS_WOBBLE_DURATION_SEC, 0.0, 1.0)
				var envelope: float = sin(progress * PI)
				wobble_offset = sin(progress * TAU * STATUS_WOBBLE_REPETITIONS) * STATUS_WOBBLE_AMPLITUDE * envelope
				if wobble_time >= STATUS_WOBBLE_DURATION_SEC:
					wobble_wait = STATUS_WOBBLE_INTERVAL_SEC
			else:
				wobble_wait = maxf(wobble_wait - delta, 0.0)
				if wobble_wait <= 0.0:
					wobble_time = 0.0

			state["wobble_wait"] = wobble_wait
			state["wobble_time"] = wobble_time

		var target_position: Vector2 = base_position + Vector2(wobble_offset, 0.0)
		var layout_weight: float = clamp(delta * STATUS_LAYOUT_LERP_SPEED, 0.0, 1.0)
		icon.position = icon.position.lerp(target_position, layout_weight)
		status_icon_states[status_name] = state


func _update_game_clock(delta: float) -> void:
	if multiplayer.multiplayer_peer != null and not NetworkManager.is_server():
		return
	game_time_total_minutes += maxf(delta, 0.0) * game_minutes_per_real_second
	game_time_minutes = _normalize_time_minutes_float(game_time_total_minutes)
	_update_clock_label()
	_update_temperature_bar()


func _update_clock_label(force: bool = false) -> void:
	var current_minute := _normalize_time_minutes(int(floor(game_time_minutes)))
	if not force and current_minute == displayed_game_minute:
		return

	displayed_game_minute = current_minute
	var hour := current_minute / 60
	var minute := current_minute % 60
	var time_text := "%02d:%02d" % [hour, minute]
	clock_time_label.text = time_text
	_update_clock_glyphs(time_text)


func _setup_clock_glyphs() -> void:
	if hud_texture == null or clock_time_label == null:
		return

	for symbol in CLOCK_GLYPH_PATHS.keys():
		var texture := load(String(CLOCK_GLYPH_PATHS[symbol])) as Texture2D
		if texture == null:
			push_warning("HUD: missing clock glyph for '%s'; fallback to label clock." % String(symbol))
			return
		_clock_glyph_textures[String(symbol)] = texture

	_clock_glyph_container = HBoxContainer.new()
	_clock_glyph_container.name = "ClockGlyphs"
	_clock_glyph_container.position = Vector2(clock_time_label.offset_left, clock_time_label.offset_top)
	_clock_glyph_container.custom_minimum_size = Vector2(
		clock_time_label.offset_right - clock_time_label.offset_left,
		clock_time_label.offset_bottom - clock_time_label.offset_top
	)
	_clock_glyph_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_clock_glyph_container.add_theme_constant_override("separation", clock_symbol_gap_px)
	_clock_glyph_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_texture.add_child(_clock_glyph_container)

	for i in range(CLOCK_LAYOUT.length()):
		var slot := TextureRect.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_clock_glyph_container.add_child(slot)
		_clock_glyph_slots.append(slot)

	clock_time_label.visible = false
	_clock_glyphs_ready = true


func _update_clock_glyphs(time_text: String) -> void:
	if not _clock_glyphs_ready:
		return
	if time_text.length() != _clock_glyph_slots.size():
		return

	for i in range(time_text.length()):
		var symbol := time_text.substr(i, 1)
		var glyph_texture := _clock_glyph_textures.get(symbol, null) as Texture2D
		if glyph_texture == null:
			return
		var slot: TextureRect = _clock_glyph_slots[i]
		slot.texture = glyph_texture
		slot.custom_minimum_size = glyph_texture.get_size() * clock_symbol_scale


func _update_temperature_bar(force: bool = false) -> void:
	if temperature_bar == null:
		return

	var temperature_value: int = int(round(get_effective_temperature_celsius()))
	if not force and temperature_value == displayed_temperature_value:
		return

	displayed_temperature_value = temperature_value
	temperature_bar.min_value = 0.0
	temperature_bar.max_value = 100.0
	temperature_bar.value = _temperature_to_bar_value(float(temperature_value))


func get_ambient_temperature_celsius() -> float:
	return _get_temperature_for_minutes(game_time_minutes)


func get_effective_temperature_celsius() -> float:
	return get_ambient_temperature_celsius() + _get_equipped_clothing_warmth()


func _get_equipped_clothing_warmth() -> float:
	if InventoryManager == null:
		return 0.0
	if not InventoryManager.has_method("get_equipped_clothing_warmth"):
		return 0.0
	return float(InventoryManager.get_equipped_clothing_warmth())


func _temperature_to_bar_value(temperature_celsius: float) -> float:
	var span: float = maxf(temperature_bar_max_celsius - temperature_bar_min_celsius, 1.0)
	return clampf((temperature_celsius - temperature_bar_min_celsius) / span * 100.0, 0.0, 100.0)


func _get_temperature_for_minutes(time_minutes: float) -> float:
	var points := _get_temperature_points()
	for i in range(points.size()):
		var current: Dictionary = points[i]
		var next: Dictionary = points[(i + 1) % points.size()]
		var current_time := float(current.get("time", 0.0))
		var next_time := float(next.get("time", 0.0))
		var span := _forward_time_delta(current_time, next_time)
		var elapsed := _forward_time_delta(current_time, time_minutes)
		if elapsed <= span:
			var weight: float = clampf(elapsed / maxf(span, 0.001), 0.0, 1.0)
			return lerpf(float(current.get("temperature", day_temperature_celsius)), float(next.get("temperature", day_temperature_celsius)), weight)
	return day_temperature_celsius


func _get_temperature_points() -> Array[Dictionary]:
	return [
		{"time": 0.0, "temperature": night_temperature_celsius},
		{"time": 5.0 * 60.0, "temperature": night_temperature_celsius - 2.0},
		{"time": 8.0 * 60.0, "temperature": morning_temperature_celsius},
		{"time": 14.0 * 60.0, "temperature": day_temperature_celsius},
		{"time": 18.5 * 60.0, "temperature": evening_temperature_celsius},
		{"time": 22.0 * 60.0, "temperature": night_temperature_celsius}
	]


func _forward_time_delta(from_minutes: float, to_minutes: float) -> float:
	var delta := _normalize_time_minutes_float(to_minutes - from_minutes)
	if is_zero_approx(delta) and not is_equal_approx(from_minutes, to_minutes):
		return float(MINUTES_PER_DAY)
	return delta


func _normalize_time_minutes(value: int) -> int:
	return posmod(value, MINUTES_PER_DAY)


func _normalize_time_minutes_float(value: float) -> float:
	var wrapped_time := fmod(value, float(MINUTES_PER_DAY))
	if wrapped_time < 0.0:
		wrapped_time += float(MINUTES_PER_DAY)
	return wrapped_time


func _resolve_start_time_minutes() -> int:
	if randomize_start_time_on_new_game and not _has_pending_saved_game_state():
		return _roll_random_start_time_minutes()
	return _normalize_time_minutes(start_hour * 60 + start_minute)


func _roll_random_start_time_minutes() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(0, MINUTES_PER_DAY - 1)


func _has_pending_saved_game_state() -> bool:
	if GameSaveManager == null:
		return false
	if not GameSaveManager.has_method("has_pending_runtime_state"):
		return false
	return bool(GameSaveManager.has_pending_runtime_state())


func get_save_key() -> String:
	return SAVE_KEY


func get_save_data() -> Dictionary:
	return {
		"game_time_minutes": game_time_minutes,
		"game_time_total_minutes": game_time_total_minutes
	}


func apply_save_data(save_data: Dictionary) -> void:
	game_time_total_minutes = maxf(
		float(save_data.get("game_time_total_minutes", save_data.get("game_time_minutes", game_time_total_minutes))),
		0.0
	)
	game_time_minutes = _normalize_time_minutes_float(game_time_total_minutes)
	_update_clock_label(true)
	_update_temperature_bar(true)


func set_game_time_minutes_of_day(minutes_of_day: float) -> void:
	var normalized_time := _normalize_time_minutes_float(minutes_of_day)
	var current_day: float = floor(game_time_total_minutes / float(MINUTES_PER_DAY))
	game_time_total_minutes = maxf(current_day * float(MINUTES_PER_DAY) + normalized_time, 0.0)
	game_time_minutes = normalized_time
	_update_clock_label(true)
	_update_temperature_bar(true)


func add_game_time_minutes(minutes_delta: float) -> void:
	game_time_total_minutes = maxf(game_time_total_minutes + minutes_delta, 0.0)
	game_time_minutes = _normalize_time_minutes_float(game_time_total_minutes)
	_update_clock_label(true)
	_update_temperature_bar(true)


func get_game_time_total_minutes() -> float:
	return game_time_total_minutes


func get_game_time_minutes_of_day() -> float:
	return game_time_minutes


func _resolve_player_node() -> Node:
	if player_path != NodePath(""):
		var by_path: Node = get_node_or_null(player_path)
		if by_path != null:
			return by_path
	return get_tree().get_first_node_in_group("player")
