extends Node2D

const SAVE_FILE_PATH: String = "user://savegame.json"
const DEFAULT_LEVEL_PATH: String = "res://level.tscn"

@onready var continue_button: Button = $CenterContainer/MenuPanel/VBox/Continue
@onready var soundtrack_player: AudioStreamPlayer = $SoundTrack


func _ready() -> void:
	_disable_soundtrack_for_headless()
	_update_continue_button_state()


func _on_new_game_pressed() -> void:
	if InventoryManager != null and InventoryManager.has_method("reset_state"):
		InventoryManager.reset_state()

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
