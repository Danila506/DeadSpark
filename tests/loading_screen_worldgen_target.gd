extends Node

signal startup_loading_progress(progress: float, status: String)
signal startup_loading_finished

var _frames := 0
var _progress := 0.15
var _finished := false


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 2:
		_progress = 0.55
		startup_loading_progress.emit(_progress, "Генерация тестового мира")
	elif _frames == 5:
		_progress = 1.0
		_finished = true
		startup_loading_progress.emit(_progress, "Готово")
		startup_loading_finished.emit()


func get_startup_loading_progress() -> float:
	return _progress


func is_startup_loading_finished() -> bool:
	return _finished
