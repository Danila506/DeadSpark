extends Node

@export_range(0.25, 16.0, 0.25) var frame_time_budget_ms: float = 3.0
@export_range(0, 32, 1) var max_node_spawn_ops_per_frame: int = 2
@export_range(1, 256, 1) var max_tasks_per_frame: int = 64
@export var enabled: bool = true
@export var debug_log: bool = false
@export var keep_recent_task_history: bool = true
@export_range(4, 128, 1) var recent_task_history_limit: int = 32

var _queue: Array[Dictionary] = []
var _task_keys := {}
var _last_frame_stats: Dictionary = {}
var _recent_tasks: Array[Dictionary] = []
var _next_sequence: int = 0


func _process(_delta: float) -> void:
	if not enabled:
		return
	process_generation_frame()


func enqueue_task(task_owner: Object, task_key: String, priority: int, payload: Dictionary) -> bool:
	if task_owner == null or task_key.is_empty():
		return false
	if _task_keys.has(task_key):
		return false

	var task := {
		"owner": task_owner,
		"key": task_key,
		"priority": priority,
		"payload": payload,
		"sequence": _next_sequence
	}
	_next_sequence += 1
	_task_keys[task_key] = true
	_queue.append(task)
	_sort_queue()
	return true


func cancel_owner_tasks(task_owner: Object) -> void:
	if task_owner == null:
		return
	for i in range(_queue.size() - 1, -1, -1):
		var task := _queue[i]
		if task.get("owner", null) == task_owner:
			_task_keys.erase(str(task.get("key", "")))
			_queue.remove_at(i)


func has_owner_tasks(task_owner: Object) -> bool:
	if task_owner == null:
		return false
	for task in _queue:
		if task.get("owner", null) == task_owner:
			return true
	return false


func get_owner_task_count(task_owner: Object) -> int:
	if task_owner == null:
		return 0
	var count := 0
	for task in _queue:
		if task.get("owner", null) == task_owner:
			count += 1
	return count


func process_generation_frame(
	time_budget_ms: float = -1.0,
	node_spawn_budget: int = -1,
	task_budget: int = -1,
	allowed_owners: Array = []
) -> Dictionary:
	var resolved_time_budget_ms := frame_time_budget_ms
	if time_budget_ms >= 0.0:
		resolved_time_budget_ms = time_budget_ms
	var time_budget_usec := int(maxf(resolved_time_budget_ms, 0.25) * 1000.0)
	var node_ops_left := max_node_spawn_ops_per_frame
	if node_spawn_budget >= 0:
		node_ops_left = maxi(0, node_spawn_budget)
	var tasks_left := max_tasks_per_frame
	if task_budget > 0:
		tasks_left = maxi(1, task_budget)
	var frame_start_usec := Time.get_ticks_usec()
	var tasks_run := 0
	var node_ops_used := 0

	while tasks_left > 0 and not _queue.is_empty():
		if Time.get_ticks_usec() - frame_start_usec >= time_budget_usec:
			break

		var task := _pop_next_task(node_ops_left, allowed_owners)
		if task.is_empty():
			break
		var key := str(task.get("key", ""))
		_task_keys.erase(key)

		var task_owner: Object = task.get("owner", null)
		if task_owner == null or not is_instance_valid(task_owner):
			continue
		if not task_owner.has_method("_run_scheduled_generation_task"):
			continue

		var budget := {
			"frame_start_usec": frame_start_usec,
			"time_budget_usec": time_budget_usec,
			"node_spawn_ops_left": node_ops_left,
			"task_budget": tasks_left
		}
		var task_start_usec := Time.get_ticks_usec()
		var result_variant: Variant = task_owner.call("_run_scheduled_generation_task", task.get("payload", {}), budget)
		var task_elapsed_usec := Time.get_ticks_usec() - task_start_usec
		var result := {}
		if result_variant is Dictionary:
			result = result_variant as Dictionary
		var used_node_ops := clampi(int(result.get("node_spawn_ops_used", 0)), 0, node_ops_left)
		node_ops_left -= used_node_ops
		node_ops_used += used_node_ops
		tasks_run += 1
		tasks_left -= 1
		_record_recent_task(task, result, task_elapsed_usec)

		if not bool(result.get("done", true)):
			_task_keys[key] = true
			task["priority"] = int(result.get("priority", task.get("priority", 0)))
			task["payload"] = result.get("payload", task.get("payload", {}))
			_queue.append(task)
			_sort_queue()

	_last_frame_stats = {
		"tasks_run": tasks_run,
		"node_spawn_ops_used": node_ops_used,
		"queue_size": _queue.size(),
		"elapsed_ms": float(Time.get_ticks_usec() - frame_start_usec) / 1000.0
	}
	if debug_log and tasks_run > 0:
		print("[WorldGenerationScheduler] ", _last_frame_stats)
	return _last_frame_stats


func get_debug_info() -> Dictionary:
	return {
		"queue_size": _queue.size(),
		"frame_time_budget_ms": frame_time_budget_ms,
		"max_node_spawn_ops_per_frame": max_node_spawn_ops_per_frame,
		"last_frame": _last_frame_stats.duplicate(),
		"recent_tasks": _recent_tasks.duplicate(true)
	}


func get_recent_task_summary() -> String:
	if _recent_tasks.is_empty():
		return "recent_tasks=[]"
	var parts: Array[String] = []
	var start_index := maxi(0, _recent_tasks.size() - 6)
	for i in range(start_index, _recent_tasks.size()):
		var task := _recent_tasks[i]
		parts.append("%s:%s:%s %.2fms done=%s" % [
			str(task.get("owner", "")),
			str(task.get("action", "")),
			str(task.get("chunk", "")),
			float(task.get("elapsed_ms", 0.0)),
			str(task.get("done", true))
		])
	return "recent_tasks=[" + " | ".join(parts) + "]"


func _sort_queue() -> void:
	_queue.sort_custom(_compare_tasks)


func _pop_next_task(node_ops_left: int, allowed_owners: Array = []) -> Dictionary:
	if node_ops_left > 0:
		for i in range(_queue.size()):
			var task: Dictionary = _queue[i]
			if not _is_task_owner_allowed(task, allowed_owners):
				continue
			_queue.remove_at(i)
			return task
		return {}

	for i in range(_queue.size()):
		var task: Dictionary = _queue[i]
		if not _is_task_owner_allowed(task, allowed_owners):
			continue
		var payload: Dictionary = task.get("payload", {})
		if bool(payload.get("uses_node_spawn_budget", false)):
			continue
		_queue.remove_at(i)
		return task
	return {}


func _is_task_owner_allowed(task: Dictionary, allowed_owners: Array) -> bool:
	if allowed_owners.is_empty():
		return true
	var owner: Object = task.get("owner", null)
	for allowed_owner in allowed_owners:
		if owner == allowed_owner:
			return true
	return false


func _compare_tasks(a: Dictionary, b: Dictionary) -> bool:
	var pa := int(a.get("priority", 0))
	var pb := int(b.get("priority", 0))
	if pa == pb:
		return int(a.get("sequence", 0)) < int(b.get("sequence", 0))
	return pa < pb


func _record_recent_task(task: Dictionary, result: Dictionary, elapsed_since_frame_start_usec: int) -> void:
	if not keep_recent_task_history:
		return
	var task_owner: Object = task.get("owner", null)
	var owner_name := "<freed>"
	if task_owner != null and is_instance_valid(task_owner) and task_owner is Node:
		owner_name = (task_owner as Node).name
	var payload: Dictionary = task.get("payload", {})
	_recent_tasks.append({
		"owner": owner_name,
		"action": str(payload.get("action", "")),
		"chunk": str(payload.get("chunk", "")),
		"elapsed_ms": float(elapsed_since_frame_start_usec) / 1000.0,
		"done": bool(result.get("done", true)),
		"node_ops": int(result.get("node_spawn_ops_used", 0)),
		"queue_size": _queue.size()
	})
	while _recent_tasks.size() > maxi(1, recent_task_history_limit):
		_recent_tasks.pop_front()
