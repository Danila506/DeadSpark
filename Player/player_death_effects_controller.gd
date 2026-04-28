extends RefCounted
class_name PlayerDeathEffectsController

const MENU_SAVE_FILE_PATH: String = "user://savegame.json"
const DEATH_FADE_IN_SEC: float = 0.9
const DEATH_HOLD_SEC: float = 0.8
const DEATH_FADE_OUT_SEC: float = 0.9

var player


func _init(owner) -> void:
	player = owner


func die() -> void:
	if player.is_dead:
		return

	player.is_dead = true
	clear_menu_continue_save()
	player._stop_walk_snow_sfx()
	Callable(self, "play_death_screen_and_go_to_menu").call_deferred()


func clear_menu_continue_save() -> void:
	if FileAccess.file_exists(MENU_SAVE_FILE_PATH):
		DirAccess.remove_absolute(MENU_SAVE_FILE_PATH)


func play_death_screen_and_go_to_menu() -> void:
	ensure_death_overlay()
	if player.death_overlay_layer == null or player.death_overlay_rect == null or player.death_overlay_label == null:
		player._go_to_menu(false)
		return

	player.death_overlay_layer.visible = true
	player.death_overlay_rect.modulate.a = 0.0
	player.death_overlay_label.modulate.a = 0.0

	var fade_in_tween: Tween = player.create_tween()
	fade_in_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade_in_tween.tween_property(player.death_overlay_rect, "modulate:a", 1.0, DEATH_FADE_IN_SEC)
	fade_in_tween.parallel().tween_property(player.death_overlay_label, "modulate:a", 1.0, DEATH_FADE_IN_SEC * 0.8)
	await fade_in_tween.finished

	await player.get_tree().create_timer(DEATH_HOLD_SEC).timeout

	var fade_out_tween: Tween = player.create_tween()
	fade_out_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade_out_tween.tween_property(player.death_overlay_rect, "modulate:a", 0.0, DEATH_FADE_OUT_SEC)
	fade_out_tween.parallel().tween_property(player.death_overlay_label, "modulate:a", 0.0, DEATH_FADE_OUT_SEC * 0.8)
	await fade_out_tween.finished

	player._go_to_menu(false)


func ensure_death_overlay() -> void:
	if player.death_overlay_layer != null and is_instance_valid(player.death_overlay_layer):
		return

	player.death_overlay_layer = CanvasLayer.new()
	player.death_overlay_layer.layer = 100
	player.death_overlay_layer.visible = false
	player.add_child(player.death_overlay_layer)

	player.death_overlay_rect = ColorRect.new()
	player.death_overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	player.death_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player.death_overlay_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	player.death_overlay_rect.modulate = Color(1.0, 1.0, 1.0, 0.0)
	player.death_overlay_layer.add_child(player.death_overlay_rect)

	player.death_overlay_label = Label.new()
	player.death_overlay_label.set_anchors_preset(Control.PRESET_CENTER)
	player.death_overlay_label.offset_left = -280.0
	player.death_overlay_label.offset_top = -48.0
	player.death_overlay_label.offset_right = 280.0
	player.death_overlay_label.offset_bottom = 48.0
	player.death_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player.death_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	player.death_overlay_label.text = "ИГРА ОКОНЧЕНА"
	player.death_overlay_label.add_theme_font_size_override("font_size", 56)
	player.death_overlay_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	player.death_overlay_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	player.death_overlay_layer.add_child(player.death_overlay_label)
