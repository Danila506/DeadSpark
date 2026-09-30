extends CanvasLayer

const MENU_SCENE_PATH := "res://Menu/Menu.tscn"
const FALLBACK_GAME_SCENE_PATH := "res://level.tscn"
const REQUEST_META := &"dead_spark_loading_request"
const MINIMUM_VISIBLE_TIME_SEC := 0.65
const COMPLETION_HOLD_SEC := 0.16
const RESOURCE_STAGE_END := 0.68

@onready var screen: Control = %Screen
@onready var loading_title: Label = %LoadingTitle
@onready var loading_hint: Label = %LoadingHint
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var progress_glow: ColorRect = %ProgressGlow

var _target_scene_path := FALLBACK_GAME_SCENE_PATH
var _action := "new_game"
var _save_path := "user://savegame.json"
var _elapsed := 0.0
var _displayed_progress := 0.0
var _target_progress := 0.0
var _resource_loaded := false
var _entering_game_scene := false
var _world_ready := false
var _completion_started := false
var _loaded_scene: PackedScene = null


func _ready() -> void:
	_read_request()
	progress_bar.value = 0.0
	progress_glow.anchor_right = 0.0
	loading_title.text = tr("ЗАГРУЗКА...")
	loading_hint.text = tr("СКОРО ВЫ СНОВА БУДЕТЕ В ИГРЕ")
	screen.modulate.a = 0.0
	create_tween().tween_property(screen, "modulate:a", 1.0, 0.22)
	await get_tree().process_frame
	_start_threaded_load()


func _process(delta: float) -> void:
	_elapsed += delta
	if not _entering_game_scene:
		if not _resource_loaded:
			_poll_threaded_load()
		if _resource_loaded:
			_target_progress = RESOURCE_STAGE_END
	elif _world_ready:
		_target_progress = 1.0

	var speed := 1.35 if not _world_ready else 3.2
	_displayed_progress = move_toward(_displayed_progress, _target_progress, delta * speed)
	_update_progress_visuals(_displayed_progress)

	if (
		not _entering_game_scene
		and _resource_loaded
		and _elapsed >= MINIMUM_VISIBLE_TIME_SEC
		and _displayed_progress >= RESOURCE_STAGE_END - 0.01
	):
		_entering_game_scene = true
		_enter_loaded_scene()

	if _world_ready and _displayed_progress >= 0.999 and not _completion_started:
		_completion_started = true
		_complete_loading()


func _read_request() -> void:
	var tree := get_tree()
	if tree == null or not tree.has_meta(REQUEST_META):
		return
	var request: Variant = tree.get_meta(REQUEST_META)
	tree.remove_meta(REQUEST_META)
	if not (request is Dictionary):
		return
	var request_data := request as Dictionary
	_target_scene_path = String(request_data.get("scene_path", FALLBACK_GAME_SCENE_PATH))
	_action = String(request_data.get("action", "new_game"))
	_save_path = String(request_data.get("save_path", "user://savegame.json"))


func _start_threaded_load() -> void:
	if _target_scene_path.is_empty() or not ResourceLoader.exists(_target_scene_path):
		_fail_loading("СЦЕНА НЕ НАЙДЕНА")
		return
	var error := ResourceLoader.load_threaded_request(
		_target_scene_path,
		"PackedScene",
		true,
		ResourceLoader.CACHE_MODE_REUSE
	)
	if error != OK:
		_fail_loading("ОШИБКА ЗАГРУЗКИ")


func _poll_threaded_load() -> void:
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_target_scene_path, progress)
	if not progress.is_empty():
		_target_progress = clampf(float(progress[0]), 0.0, 1.0) * RESOURCE_STAGE_END
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			var resource := ResourceLoader.load_threaded_get(_target_scene_path)
			if resource is PackedScene:
				_loaded_scene = resource as PackedScene
				_resource_loaded = true
				_target_progress = RESOURCE_STAGE_END
			else:
				_fail_loading("ОШИБКА ЗАГРУЗКИ")
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail_loading("ОШИБКА ЗАГРУЗКИ")


func _update_progress_visuals(progress: float) -> void:
	var normalized := clampf(progress, 0.0, 1.0)
	progress_bar.value = normalized * 100.0
	progress_glow.anchor_right = normalized
	progress_glow.visible = normalized > 0.015


func _enter_loaded_scene() -> void:
	if _action == "continue" and GameSaveManager != null and GameSaveManager.has_method("prepare_load_game"):
		var preparation: Dictionary = GameSaveManager.prepare_load_game(_save_path)
		if int(preparation.get("error", FAILED)) != OK:
			_fail_loading("НЕ УДАЛОСЬ ЗАГРУЗИТЬ СОХРАНЕНИЕ")
			return
		var prepared_path := String(preparation.get("scene_path", _target_scene_path))
		if prepared_path != _target_scene_path:
			_fail_loading("СОХРАНЕНИЕ ИЗМЕНИЛОСЬ")
			return

	var tree := get_tree()
	# The CanvasLayer becomes a root child before the transition, so it remains
	# visible while level.gd performs its asynchronous startup generation.
	reparent(tree.root)
	if NodeCleanupQueue != null and NodeCleanupQueue.has_method("begin_scene_transition"):
		NodeCleanupQueue.begin_scene_transition()
	var error := tree.change_scene_to_packed(_loaded_scene)
	if error != OK:
		_fail_loading("ОШИБКА ЗАПУСКА")
		return
	await tree.scene_changed
	var destination := tree.current_scene
	if destination == null:
		_fail_loading("ОШИБКА ЗАПУСКА")
		return

	if destination.has_signal("startup_loading_progress"):
		destination.connect("startup_loading_progress", Callable(self, "_on_startup_loading_progress"))
		if destination.has_method("get_startup_loading_progress"):
			_on_startup_loading_progress(float(destination.call("get_startup_loading_progress")), "")
	if destination.has_signal("startup_loading_finished"):
		destination.connect("startup_loading_finished", Callable(self, "_on_startup_loading_finished"), CONNECT_ONE_SHOT)
		if destination.has_method("is_startup_loading_finished") and bool(destination.call("is_startup_loading_finished")):
			_on_startup_loading_finished()
	else:
		_on_startup_loading_finished()


func _on_startup_loading_progress(progress: float, _status: String) -> void:
	_target_progress = RESOURCE_STAGE_END + clampf(progress, 0.0, 1.0) * (1.0 - RESOURCE_STAGE_END)


func _on_startup_loading_finished() -> void:
	_world_ready = true
	_target_progress = 1.0


func _complete_loading() -> void:
	await get_tree().create_timer(COMPLETION_HOLD_SEC).timeout
	var fade := create_tween()
	fade.tween_property(screen, "modulate:a", 0.0, 0.2)
	await fade.finished
	queue_free()


func _fail_loading(message: String) -> void:
	set_process(false)
	loading_title.text = tr(message)
	loading_hint.text = tr("ВОЗВРАЩЕНИЕ В ГЛАВНОЕ МЕНЮ")
	push_error("LoadingScreen: %s (%s)" % [message, _target_scene_path])
	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file(MENU_SCENE_PATH)
	queue_free()
