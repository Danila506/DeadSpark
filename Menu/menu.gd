extends Node2D

const SAVE_FILE_PATH: String = "user://savegame.json"
const DEFAULT_LEVEL_PATH: String = "res://level.tscn"
const DONATE_URL: String = "https://boosty.to/deadspark/donate"

@onready var continue_button: Button = $CenterContainer/MenuPanel/VBox/Continue
@onready var soundtrack_player: AudioStreamPlayer = $SoundTrack
@onready var background_rect: ColorRect = $Background
@onready var glow_top_rect: ColorRect = $GlowTop
@onready var center_container: CenterContainer = $CenterContainer


func _ready() -> void:
	_disable_soundtrack_for_headless()
	_fit_menu_to_viewport()
	if not get_viewport().size_changed.is_connected(_fit_menu_to_viewport):
		get_viewport().size_changed.connect(_fit_menu_to_viewport)
	_update_continue_button_state()


func _fit_menu_to_viewport() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size == Vector2.ZERO:
		return

	if background_rect != null:
		background_rect.position = Vector2.ZERO
		background_rect.size = viewport_size

	if glow_top_rect != null:
		glow_top_rect.position = Vector2.ZERO
		glow_top_rect.size = Vector2(viewport_size.x, maxf(viewport_size.y * 0.46, 1.0))

	if center_container != null:
		center_container.position = Vector2.ZERO
		center_container.size = viewport_size


func _on_new_game_pressed() -> void:
	if InventoryManager != null and InventoryManager.has_method("reset_state"):
		InventoryManager.reset_state()

	if GameSaveManager != null and GameSaveManager.has_method("start_new_game"):
		GameSaveManager.start_new_game(DEFAULT_LEVEL_PATH, SAVE_FILE_PATH)
	else:
		_write_save(DEFAULT_LEVEL_PATH)
	get_tree().change_scene_to_file(DEFAULT_LEVEL_PATH)


func _on_continue_pressed() -> void:
	if GameSaveManager != null and GameSaveManager.has_method("load_game"):
		var load_result: int = int(GameSaveManager.load_game())
		if load_result == OK:
			return

	var save_data: Dictionary = _read_save()
	if save_data.is_empty():
		_update_continue_button_state()
		return

	var scene_path: String = String(save_data.get("scene_path", DEFAULT_LEVEL_PATH))
	if scene_path.is_empty():
		scene_path = DEFAULT_LEVEL_PATH

	if not ResourceLoader.exists(scene_path):
		scene_path = DEFAULT_LEVEL_PATH

	get_tree().change_scene_to_file(scene_path)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_donate_pressed() -> void:
	OS.shell_open(DONATE_URL)


func _disable_soundtrack_for_headless() -> void:
	if soundtrack_player == null:
		return
	if DisplayServer.get_name() != "headless":
		return
	if soundtrack_player.playing:
		soundtrack_player.stop()
	soundtrack_player.autoplay = false
	soundtrack_player.stream = null


func _exit_tree() -> void:
	if soundtrack_player == null:
		return
	if soundtrack_player.playing:
		soundtrack_player.stop()
	# Release stream reference to avoid playback resources lingering on shutdown.
	soundtrack_player.stream = null


func _update_continue_button_state() -> void:
	if continue_button == null:
		return

	continue_button.disabled = not FileAccess.file_exists(SAVE_FILE_PATH)


func _write_save(scene_path: String) -> void:
	var file: FileAccess = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file == null:
		return

	var data: Dictionary = {
		"scene_path": scene_path,
		"saved_at_unix": Time.get_unix_time_from_system()
	}
	file.store_string(JSON.stringify(data))
	file.flush()


func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		return {}

	var file: FileAccess = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file == null:
		return {}

	var raw_json: String = file.get_as_text()
	if raw_json.is_empty():
		return {}

	var parsed: Variant = JSON.parse_string(raw_json)
	if parsed is Dictionary:
		return parsed

	return {}
