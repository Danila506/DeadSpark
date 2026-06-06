extends Node

@export var enabled: bool = true
@export var spike_threshold_ms: float = 25.0
@export var freeze_threshold_ms: float = 120.0
@export var log_cooldown_sec: float = 0.5
@export var summary_interval_sec: float = 5.0
@export var log_to_file: bool = true
@export var log_file_path: String = "user://logs/stutter_monitor.log"
@export var include_scheduler_details: bool = true
@export var orphan_context_threshold: int = 1000
@export var low_node_count_context_threshold: int = 64

var _cooldown_left: float = 0.0
var _summary_left: float = 0.0
var _max_frame_ms_since_summary: float = 0.0
var _spike_count_since_summary: int = 0
var _freeze_count_since_summary: int = 0
var _session_start_ms: int = 0


func _ready() -> void:
	_session_start_ms = Time.get_ticks_msec()
	_summary_left = maxf(summary_interval_sec, 0.25)
	if not enabled:
		return

	_prepare_log_file()
	if not get_tree().scene_changed.is_connected(_on_scene_changed):
		get_tree().scene_changed.connect(_on_scene_changed)
	var scene_path := ""
	if get_tree().current_scene != null:
		scene_path = String(get_tree().current_scene.scene_file_path)
	_log_line(
		"[STUTTER_MONITOR] enabled=true threshold_ms=%.1f freeze_ms=%.1f summary_sec=%.1f log=%s scene=%s" % [
			spike_threshold_ms,
			freeze_threshold_ms,
			summary_interval_sec,
			ProjectSettings.globalize_path(log_file_path),
			scene_path
		]
	)


func _process(delta: float) -> void:
	if not enabled:
		return

	var frame_ms: float = delta * 1000.0
	_max_frame_ms_since_summary = maxf(_max_frame_ms_since_summary, frame_ms)
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_summary_left = maxf(_summary_left - delta, 0.0)

	if frame_ms >= freeze_threshold_ms:
		_freeze_count_since_summary += 1
	if frame_ms >= spike_threshold_ms:
		_spike_count_since_summary += 1

	if frame_ms >= spike_threshold_ms and _cooldown_left <= 0.0:
		_cooldown_left = maxf(log_cooldown_sec, 0.0)
		_log_snapshot("FREEZE" if frame_ms >= freeze_threshold_ms else "SPIKE", frame_ms)

	if _summary_left <= 0.0:
		_summary_left = maxf(summary_interval_sec, 0.25)
		_log_summary(frame_ms)


func _exit_tree() -> void:
	if not enabled:
		return
	_log_summary(0.0, true)
	_log_line("[STUTTER_MONITOR] session_end uptime_ms=%d" % max(Time.get_ticks_msec() - _session_start_ms, 0))


func _log_summary(last_frame_ms: float, force: bool = false) -> void:
	if not force and _spike_count_since_summary <= 0 and _freeze_count_since_summary <= 0 and _max_frame_ms_since_summary < spike_threshold_ms:
		return
	var snapshot := _collect_snapshot(last_frame_ms)
	_log_line(
		"[STUTTER_SUMMARY] t=%dms spikes=%d freezes=%d max_frame=%.2fms avg_fps=%d frame=%.2fms process=%.2fms physics=%.2fms draws=%d render_objs=%d nodes=%d orphans=%d static_mb=%.2f vram_mb=%.2f msg_mb=%.2f chunks=%d pending=%d scheduler_queue=%d scheduler_ms=%.2f recent=%s" % [
			max(Time.get_ticks_msec() - _session_start_ms, 0),
			_spike_count_since_summary,
			_freeze_count_since_summary,
			_max_frame_ms_since_summary,
			snapshot["fps"],
			snapshot["frame_ms"],
			snapshot["process_ms"],
			snapshot["physics_ms"],
			snapshot["draw_calls"],
			snapshot["render_objects"],
			snapshot["node_count"],
			snapshot["orphan_node_count"],
			snapshot["static_mem_mb"],
			snapshot["video_mem_mb"],
			snapshot["message_buffer_mb"],
			snapshot["loaded_chunks"],
			snapshot["pending_chunks"],
			snapshot["scheduler_queue"],
			snapshot["scheduler_ms"],
			snapshot["scheduler_recent"]
		]
	)
	_max_frame_ms_since_summary = 0.0
	_spike_count_since_summary = 0
	_freeze_count_since_summary = 0


func _log_snapshot(kind: String, frame_ms: float) -> void:
	var snapshot := _collect_snapshot(frame_ms)
	_log_line(
		"[STUTTER_%s] t=%dms frame=%.2fms fps=%d process=%.2fms physics=%.2fms draws=%d render_objs=%d nodes=%d orphans=%d objects=%d static_mb=%.2f vram_mb=%.2f msg_mb=%.2f chunks=%d pending=%d scheduler_queue=%d scheduler_tasks=%d scheduler_ms=%.2f recent=%s" % [
			kind,
			max(Time.get_ticks_msec() - _session_start_ms, 0),
			snapshot["frame_ms"],
			snapshot["fps"],
			snapshot["process_ms"],
			snapshot["physics_ms"],
			snapshot["draw_calls"],
			snapshot["render_objects"],
			snapshot["node_count"],
			snapshot["orphan_node_count"],
			snapshot["object_count"],
			snapshot["static_mem_mb"],
			snapshot["video_mem_mb"],
			snapshot["message_buffer_mb"],
			snapshot["loaded_chunks"],
			snapshot["pending_chunks"],
			snapshot["scheduler_queue"],
			snapshot["scheduler_tasks"],
			snapshot["scheduler_ms"],
			snapshot["scheduler_recent"]
		]
	)
	_log_orphan_context_if_needed(kind, snapshot)


func _collect_snapshot(frame_ms: float) -> Dictionary:
	var scheduler_info := _collect_scheduler_info()
	var chunk_info := _collect_world_generation_info()
	return {
		"fps": Engine.get_frames_per_second(),
		"frame_ms": snappedf(frame_ms, 0.01),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_node_count": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"render_objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"static_mem_mb": _bytes_to_mb(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"message_buffer_mb": _bytes_to_mb(Performance.get_monitor(Performance.MEMORY_MESSAGE_BUFFER_MAX)),
		"video_mem_mb": _bytes_to_mb(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"loaded_chunks": int(chunk_info.get("loaded", 0)),
		"pending_chunks": int(chunk_info.get("pending", 0)),
		"scheduler_queue": int(scheduler_info.get("queue_size", 0)),
		"scheduler_tasks": int(scheduler_info.get("tasks_run", 0)),
		"scheduler_ms": snappedf(float(scheduler_info.get("elapsed_ms", 0.0)), 0.01),
		"scheduler_recent": String(scheduler_info.get("recent", ""))
	}


func _collect_scheduler_info() -> Dictionary:
	if not include_scheduler_details:
		return {}
	var scheduler := get_node_or_null("/root/WorldGenerationScheduler")
	if scheduler == null or not scheduler.has_method("get_debug_info"):
		return {}

	var info: Dictionary = scheduler.call("get_debug_info")
	var last_frame: Dictionary = info.get("last_frame", {})
	return {
		"queue_size": int(info.get("queue_size", 0)),
		"tasks_run": int(last_frame.get("tasks_run", 0)),
		"elapsed_ms": float(last_frame.get("elapsed_ms", 0.0)),
		"recent": scheduler.call("get_recent_task_summary") if scheduler.has_method("get_recent_task_summary") else ""
	}


func _collect_world_generation_info() -> Dictionary:
	var root := _resolve_world_generation_root()
	if root == null:
		return {"loaded": 0, "pending": 0}

	var loaded_total := 0
	var pending_total := 0
	for child in root.get_children():
		if not child.has_method("get_debug_world_generation_info"):
			continue
		var info_variant: Variant = child.call("get_debug_world_generation_info")
		if not (info_variant is Dictionary):
			continue
		var info := info_variant as Dictionary
		var loaded: Variant = info.get("loaded_chunks", [])
		if loaded is Array:
			loaded_total += (loaded as Array).size()
		if child.has_method("get_pending_generation_chunk_count"):
			pending_total += int(child.call("get_pending_generation_chunk_count"))
		else:
			pending_total += int(info.get("pending_load", 0))
			pending_total += int(info.get("pending_unload", 0))
	return {"loaded": loaded_total, "pending": pending_total}


func _resolve_world_generation_root() -> Node:
	if get_tree().current_scene == null:
		return null
	return get_tree().current_scene.get_node_or_null("WorldGeneration")


func _on_scene_changed() -> void:
	var scene_path := ""
	if get_tree().current_scene != null:
		scene_path = String(get_tree().current_scene.scene_file_path)
	append_log_file_only("[SCENE_CHANGED] t=%dms scene=%s" % [
		max(Time.get_ticks_msec() - _session_start_ms, 0),
		scene_path
	])


func _log_orphan_context_if_needed(kind: String, snapshot: Dictionary) -> void:
	var orphan_count := int(snapshot.get("orphan_node_count", 0))
	var node_count := int(snapshot.get("node_count", 0))
	if orphan_count < orphan_context_threshold and node_count > low_node_count_context_threshold:
		return

	var scene_path := ""
	var root_child_count := 0
	if get_tree().current_scene != null:
		scene_path = String(get_tree().current_scene.scene_file_path)
		root_child_count = get_tree().current_scene.get_child_count()

	var cleanup_pending := 0
	var cleanup_total_enqueued := 0
	var cleanup_total_freed := 0
	var cleanup_queue := get_node_or_null("/root/NodeCleanupQueue")
	if cleanup_queue != null and cleanup_queue.has_method("get_debug_info"):
		var cleanup_info: Dictionary = cleanup_queue.call("get_debug_info")
		cleanup_pending = int(cleanup_info.get("pending", 0))
		cleanup_total_enqueued = int(cleanup_info.get("total_enqueued", 0))
		cleanup_total_freed = int(cleanup_info.get("total_freed", 0))

	var player_count := get_tree().get_nodes_in_group("player").size()
	var player_dead := false
	var player := get_tree().get_first_node_in_group("player")
	if player != null and "is_dead" in player:
		player_dead = bool(player.is_dead)

	append_log_file_only("[STUTTER_CONTEXT] kind=%s t=%dms scene=%s root_children=%d paused=%s cleanup_pending=%d cleanup_enqueued=%d cleanup_freed=%d player_count=%d player_dead=%s" % [
		kind,
		max(Time.get_ticks_msec() - _session_start_ms, 0),
		scene_path,
		root_child_count,
		str(get_tree().paused),
		cleanup_pending,
		cleanup_total_enqueued,
		cleanup_total_freed,
		player_count,
		str(player_dead)
	])


func _prepare_log_file() -> void:
	if not log_to_file:
		return
	var log_dir := log_file_path.get_base_dir()
	if not log_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(log_dir)
	var file := FileAccess.open(log_file_path, FileAccess.WRITE)
	if file == null:
		push_warning("StutterMonitor: failed to open log file at %s" % log_file_path)
		return
	file.store_line("# DeadSpark stutter monitor log")
	file.store_line("# " + Time.get_datetime_string_from_system())
	file.flush()
	file.close()


func _log_line(text: String) -> void:
	print(text)
	_append_log_file_line(text)


func append_log_file_only(text: String) -> void:
	_append_log_file_line(text)


func _append_log_file_line(text: String) -> void:
	if not log_to_file:
		return
	var file := FileAccess.open(log_file_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(text)
	file.flush()
	file.close()


func _bytes_to_mb(value: float) -> float:
	return snappedf(value / (1024.0 * 1024.0), 0.01)
