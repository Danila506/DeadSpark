extends RefCounted
class_name PlayerStatusHintController

const LOW_NEED_HINT_THRESHOLD_RATIO: float = 0.5
const LOW_NEED_HINT_INTERVAL_SEC: float = 30.0
const LOW_WATER_HINT_TEXT: String = "Я хочу пить"
const LOW_FOOD_HINT_TEXT: String = "Я хочу есть"
const LOW_WATER_HINT_COLOR: Color = Color(0.45, 0.8, 1.0, 1.0)
const LOW_FOOD_HINT_COLOR: Color = Color(0.9, 0.8, 0.62, 1.0)

var player


func _init(owner) -> void:
	player = owner


func ensure_status_hint_label() -> void:
	if player.status_hint_label != null:
		return

	player.status_hint_label = Label.new()
	player.status_hint_label.text = ""
	player.status_hint_label.visible = false
	player.status_hint_label.position = player.status_hint_base_position
	player.status_hint_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	player.status_hint_label.z_index = 50
	player.status_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player.status_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	player.status_hint_label.add_theme_font_size_override("font_size", 11)
	player.status_hint_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	player.add_child(player.status_hint_label)


func update_low_need_hints(delta: float) -> void:
	var is_low_water: bool = player.max_water > 0.0 and (player.water / player.max_water) < LOW_NEED_HINT_THRESHOLD_RATIO
	var is_low_food: bool = player.max_food > 0.0 and (player.food / player.max_food) < LOW_NEED_HINT_THRESHOLD_RATIO

	if is_low_water:
		if not player.was_low_water:
			enqueue_status_hint(LOW_WATER_HINT_TEXT, LOW_WATER_HINT_COLOR)
			player.low_water_hint_timer = 0.0
		player.low_water_hint_timer += delta
		if player.low_water_hint_timer >= LOW_NEED_HINT_INTERVAL_SEC:
			player.low_water_hint_timer = 0.0
			enqueue_status_hint(LOW_WATER_HINT_TEXT, LOW_WATER_HINT_COLOR)
	else:
		player.low_water_hint_timer = 0.0

	if is_low_food:
		if not player.was_low_food:
			enqueue_status_hint(LOW_FOOD_HINT_TEXT, LOW_FOOD_HINT_COLOR)
			player.low_food_hint_timer = 0.0
		player.low_food_hint_timer += delta
		if player.low_food_hint_timer >= LOW_NEED_HINT_INTERVAL_SEC:
			player.low_food_hint_timer = 0.0
			enqueue_status_hint(LOW_FOOD_HINT_TEXT, LOW_FOOD_HINT_COLOR)
	else:
		player.low_food_hint_timer = 0.0

	player.was_low_water = is_low_water
	player.was_low_food = is_low_food

	if player.status_hint_time_left <= 0.0 and not player.status_hint_queue.is_empty():
		start_status_hint(player.status_hint_queue.pop_front())


func enqueue_status_hint(text: String, color: Color) -> void:
	if text.is_empty():
		return
	if player.status_hint_label != null and player.status_hint_label.visible and player.status_hint_label.text == text:
		return
	for queued_hint in player.status_hint_queue:
		if String(queued_hint.get("text", "")) == text:
			return
	player.status_hint_queue.append({
		"text": text,
		"color": color
	})


func start_status_hint(hint_data: Dictionary) -> void:
	if player.status_hint_label == null:
		return

	var text: String = String(hint_data.get("text", ""))
	var color: Color = hint_data.get("color", Color(0.95, 0.95, 0.95, 1.0))
	if text.is_empty():
		return

	player.status_hint_label.text = text
	player.status_hint_label.add_theme_color_override("font_color", color)
	player.status_hint_label.visible = true
	player.status_hint_label.position = player.status_hint_base_position
	player.status_hint_label.modulate.a = 0.0
	player.status_hint_time_left = player.status_hint_total_duration


func update_status_hint_visual(delta: float) -> void:
	if player.status_hint_label == null:
		return
	if player.status_hint_time_left <= 0.0:
		player.status_hint_label.visible = false
		player.status_hint_label.modulate.a = 0.0
		return

	player.status_hint_time_left = max(player.status_hint_time_left - delta, 0.0)
	var elapsed: float = player.status_hint_total_duration - player.status_hint_time_left
	var progress: float = clamp(elapsed / max(player.status_hint_total_duration, 0.01), 0.0, 1.0)

	var fade_in_ratio: float = 0.2
	var fade_out_ratio: float = 0.2
	var alpha: float = 1.0
	if progress < fade_in_ratio:
		alpha = progress / max(fade_in_ratio, 0.001)
	elif progress > (1.0 - fade_out_ratio):
		alpha = (1.0 - progress) / max(fade_out_ratio, 0.001)

	player.status_hint_label.modulate.a = clamp(alpha, 0.0, 1.0)
	player.status_hint_label.position = player.status_hint_base_position + Vector2(0.0, -8.0 * progress)

	if player.status_hint_time_left <= 0.0:
		player.status_hint_label.visible = false
		player.status_hint_label.modulate.a = 0.0
