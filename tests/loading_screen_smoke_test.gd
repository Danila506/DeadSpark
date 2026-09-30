extends SceneTree

const LOADING_SCENE_PATH := "res://Menu/loading.tscn"
const TARGET_SCENE_PATH := "res://tests/loading_screen_worldgen_target.tscn"
const REQUEST_META := &"dead_spark_loading_request"
const TIMEOUT_SEC := 5.0

var _elapsed := 0.0
var _saw_loading_scene := false
var _saw_persistent_overlay := false


func _initialize() -> void:
	if ResourceLoader.load("res://level.gd", "Script") == null:
		printerr("Loading screen smoke test could not compile level.gd")
		quit(1)
		return
	set_meta(REQUEST_META, {
		"scene_path": TARGET_SCENE_PATH,
		"action": "new_game",
		"save_path": "user://loading_screen_smoke_unused.json",
	})
	change_scene_to_file.call_deferred(LOADING_SCENE_PATH)


func _process(delta: float) -> bool:
	_elapsed += delta
	if current_scene != null:
		if current_scene.scene_file_path == LOADING_SCENE_PATH:
			_saw_loading_scene = true
		elif _saw_loading_scene and current_scene.scene_file_path == TARGET_SCENE_PATH:
			var overlay := root.get_node_or_null("LoadingOverlay")
			if overlay != null:
				_saw_persistent_overlay = true
				return false
			if not _saw_persistent_overlay:
				printerr("Loading overlay did not remain visible during world generation")
				quit(1)
				return true
			print("Loading screen smoke test passed")
			quit(0)
			return true
	if _elapsed >= TIMEOUT_SEC:
		printerr("Loading screen smoke test timed out")
		quit(1)
	return false
