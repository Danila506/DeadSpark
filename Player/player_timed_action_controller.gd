extends RefCounted
class_name PlayerTimedActionController

var player


func _init(owner) -> void:
	player = owner


func start_timed_action(duration: float, on_complete: Callable, _label: String = "", blocks_movement: bool = true, action_animation_name: String = "") -> bool:
	if player.action_in_progress:
		return false

	player.action_in_progress = true
	player.action_blocks_movement = blocks_movement
	player.action_duration = max(duration, 0.01)
	player.action_elapsed = 0.0
	player.action_complete_callback = on_complete
	player.current_action_animation = action_animation_name.strip_edges()
	show_action_bar(player.action_duration)
	player._force_refresh_animation()
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

	var callback: Callable = player.action_complete_callback
	player.action_complete_callback = Callable()
	if callback.is_valid():
		callback.call()


func show_action_bar(duration: float) -> void:
	if player.action_bar_root == null or player.action_bar_fill == null:
		return

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

	player.action_bar_root.visible = false
	player.action_bar_fill.value = 0.0
