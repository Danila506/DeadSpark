extends RefCounted
class_name PlayerTimedActionController

var player
var cancellation_callback := Callable()
var cancel_hint: Label


func _init(owner) -> void:
	player = owner


func start_timed_action(duration: float, on_complete: Callable, _label: String = "", blocks_movement: bool = true, action_animation_name: String = "", on_cancel: Callable = Callable()) -> bool:
	if player.action_in_progress:
		return false

	cancellation_callback = on_cancel
	player.action_in_progress = true
	player.action_blocks_movement = blocks_movement
	player.action_duration = max(duration, 0.01)
	player.action_elapsed = 0.0
	player.action_complete_callback = on_complete
	player.current_action_animation = action_animation_name.strip_edges()
	if player.current_action_animation.is_empty():
		player.current_action_animation = "Using"
	show_action_bar(player.action_duration)
	player._force_refresh_animation()
	player._sync_timed_action_state()
	return true


func cancel_timed_action(expected_callback: Callable = Callable()) -> bool:
	if not player.action_in_progress:
		return false

	if expected_callback.is_valid():
		if not player.action_complete_callback.is_valid():
			return false
		if player.action_complete_callback.get_object_id() != expected_callback.get_object_id():
			return false
		if player.action_complete_callback.get_method() != expected_callback.get_method():
			return false

	player.action_in_progress = false
	player.action_blocks_movement = true
	player.action_duration = 0.0
	player.action_elapsed = 0.0
	player.action_complete_callback = Callable()
	player.current_action_animation = ""
	hide_action_bar()
	player._force_refresh_animation()
	player._sync_timed_action_state()
	var cancelled := cancellation_callback
	cancellation_callback = Callable()
	if cancelled.is_valid(): cancelled.call()
	return true


func update_timed_action(delta: float) -> void:
	if not player.action_in_progress:
		return

	player.action_elapsed += delta
	var progress: float = clamp(player.action_elapsed / max(player.action_duration, 0.01), 0.0, 1.0)
	set_action_progress(progress)

	if progress < 1.0:
		return

	player.action_in_progress = false
	player.action_blocks_movement = true
	player.action_duration = 0.0
	player.action_elapsed = 0.0
	player.current_action_animation = ""
	hide_action_bar()
	player._force_refresh_animation()
	player._sync_timed_action_state()

	cancellation_callback = Callable()
	var callback: Callable = player.action_complete_callback
	player.action_complete_callback = Callable()
	if callback.is_valid():
		callback.call()


func show_action_bar(duration: float) -> void:
	if player.action_bar_root == null or player.action_bar_fill == null:
		return

	if not is_instance_valid(cancel_hint):
		cancel_hint = Label.new()
		cancel_hint.text = "[E] - отменить"
		cancel_hint.position = Vector2(-45, -16)
		cancel_hint.size = Vector2(125, 20)
		cancel_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cancel_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cancel_hint.add_theme_font_size_override("font_size", 14)
		cancel_hint.add_theme_color_override("font_outline_color", Color.BLACK)
		cancel_hint.add_theme_constant_override("outline_size", 3)
		player.action_bar_root.add_child(cancel_hint)
	cancel_hint.visible = cancellation_callback.is_valid()
	player.action_bar_root.visible = true
	player.action_bar_fill.max_value = max(duration, 0.01)
	player.action_bar_fill.value = 0.0


func set_action_progress(progress_ratio: float) -> void:
	if player.action_bar_root == null or player.action_bar_fill == null:
		return

	player.action_bar_root.visible = true
	player.action_bar_fill.value = clamp(progress_ratio, 0.0, 1.0) * player.action_bar_fill.max_value


func hide_action_bar() -> void:
	if player.action_bar_root == null or player.action_bar_fill == null:
		return

	if is_instance_valid(cancel_hint):
		cancel_hint.visible = false
	player.action_bar_root.visible = false
	player.action_bar_fill.value = 0.0
