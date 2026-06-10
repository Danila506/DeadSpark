extends CanvasLayer

@export var player_path: NodePath
@export_range(0, 23, 1) var start_hour: int = 8
@export_range(0, 59, 1) var start_minute: int = 0
@export_range(0.05, 60.0, 0.05) var game_minutes_per_real_second: float = 1.0
@export var randomize_start_time_on_new_game: bool = true
@export_range(0, 8, 1) var clock_symbol_gap_px: int = 1
@export_range(0.5, 4.0, 0.1) var clock_symbol_scale: float = 1

var player: Node = null

@onready var health_bar: TextureProgressBar = $HealthBar
@onready var water_bar: TextureProgressBar = $WaterBar
@onready var food_bar: TextureProgressBar = $FoodBar
@onready var stamina_bar: TextureProgressBar = $StaminaBar
@onready var clock_time_label: Label = $HUDTexture/ClockTimeLabel
@onready var hud_texture: TextureRect = $HUDTexture
@onready var bleeding_icon: Sprite2D = $HUDTexture/Bleeding
@onready var fracture_icon: Sprite2D = $HUDTexture/Fracture
@onready var disease_icon: Sprite2D = $HUDTexture/Disease
@onready var regeneration_icon: Sprite2D = $HUDTexture/Regeneration

const MINUTES_PER_DAY: int = 24 * 60
const SAVE_KEY: String = "hud_game_clock"
const STATUS_SHAKE_AMPLITUDE: float = 1.5
const STATUS_SHAKE_SPEED: float = 18.0
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
var bleeding_blink_timer: float = 0.0
var bleeding_blink_visible: bool = false
var fracture_blink_timer: float = 0.0
var fracture_blink_visible: bool = false
var _clock_glyph_textures: Dictionary = {}
var _clock_glyph_slots: Array[TextureRect] = []
var _clock_glyph_container: HBoxContainer = null
var _clock_glyphs_ready: bool = false
var _status_shake_time: float = 0.0
var _status_icon_base_positions: Dictionary = {}


func _ready() -> void:
	_setup_clock_glyphs()
	_cache_status_icon_base_positions()
	add_to_group("game_clock")
	game_time_total_minutes = float(_resolve_start_time_minutes())
	game_time_minutes = _normalize_time_minutes_float(game_time_total_minutes)
	_update_clock_label(true)

	player = _resolve_player_node()
	if player == null:
		push_error("HUD: player not found (player_path/group 'player').")
		return
	player.stats_changed.connect(update_stats)
	if player.has_signal("status_effects_changed"):
		player.status_effects_changed.connect(update_status_effects)
	bleeding_icon.visible = false
	fracture_icon.visible = false
	disease_icon.visible = false
	regeneration_icon.visible = false
	update_stats()
	update_status_effects()


func _process(delta: float) -> void:
	_status_shake_time += maxf(delta, 0.0)
	_update_game_clock(delta)
	_update_bleeding_blink(delta)
	_update_fracture_blink(delta)
	_update_status_icon_shake()


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

	if not player.is_bleeding:
		bleeding_icon.visible = false
		bleeding_blink_timer = 0.0
		bleeding_blink_visible = false
		_reset_status_icon_position(bleeding_icon)

	if not ("is_fractured" in player and player.is_fractured):
		fracture_icon.visible = false
		fracture_blink_timer = 0.0
		fracture_blink_visible = false
		_reset_status_icon_position(fracture_icon)

	regeneration_icon.visible = player.has_method("has_passive_regeneration") and player.has_passive_regeneration()
	disease_icon.visible = "is_diseased" in player and player.is_diseased
	if not disease_icon.visible:
		_reset_status_icon_position(disease_icon)
	_reset_status_icon_position(regeneration_icon)


func _update_bleeding_blink(delta: float) -> void:
	if player == null or not player.is_bleeding:
		return

	bleeding_blink_timer += delta
	if bleeding_blink_timer >= 1.0:
		bleeding_blink_timer = 0.0
		bleeding_blink_visible = not bleeding_blink_visible

	bleeding_icon.visible = bleeding_blink_visible


func _update_fracture_blink(delta: float) -> void:
	if player == null or not ("is_fractured" in player and player.is_fractured):
		return

	fracture_blink_timer += delta
	if fracture_blink_timer >= 1.0:
		fracture_blink_timer = 0.0
		fracture_blink_visible = not fracture_blink_visible

	fracture_icon.visible = fracture_blink_visible


func _cache_status_icon_base_positions() -> void:
	_status_icon_base_positions = {
		bleeding_icon: bleeding_icon.position,
		fracture_icon: fracture_icon.position,
		disease_icon: disease_icon.position,
		regeneration_icon: regeneration_icon.position
	}


func _update_status_icon_shake() -> void:
	_update_icon_shake(bleeding_icon, player != null and player.is_bleeding)
	_update_icon_shake(fracture_icon, player != null and ("is_fractured" in player and player.is_fractured))
	_update_icon_shake(disease_icon, player != null and ("is_diseased" in player and player.is_diseased))
	_reset_status_icon_position(regeneration_icon)


func _update_icon_shake(icon: Sprite2D, is_active: bool) -> void:
	if not is_active:
		_reset_status_icon_position(icon)
		return

	var base_position: Vector2 = _status_icon_base_positions.get(icon, icon.position)
	var phase: float = float(icon.get_instance_id() % 10) * 0.45
	var shake_offset := Vector2(
		sin(_status_shake_time * STATUS_SHAKE_SPEED + phase),
		cos(_status_shake_time * STATUS_SHAKE_SPEED * 1.25 + phase)
	) * STATUS_SHAKE_AMPLITUDE
	icon.position = base_position + shake_offset


func _reset_status_icon_position(icon: Sprite2D) -> void:
	var base_position: Vector2 = _status_icon_base_positions.get(icon, icon.position)
	icon.position = base_position


func _update_game_clock(delta: float) -> void:
	game_time_total_minutes += maxf(delta, 0.0) * game_minutes_per_real_second
	game_time_minutes = _normalize_time_minutes_float(game_time_total_minutes)
	_update_clock_label()


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
