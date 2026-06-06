extends Node

@export var enabled: bool = true
@export var log_all_operations: bool = false
@export var spike_threshold_ms: float = 150.0
@export var destructive_operation_threshold: int = 9999
@export var mirror_to_console: bool = false


func record_chunk_operation(source_name: String, action: String, chunk: Vector2i, stats: Dictionary) -> void:
	if not enabled:
		return

	var elapsed_ms := float(stats.get("elapsed_ms", 0.0))
	var cells_erased := int(stats.get("cells_erased", 0)) + int(stats.get("overlap_erased", 0))
	var nodes_freed := int(stats.get("nodes_freed", 0))
	var should_log := log_all_operations or elapsed_ms >= spike_threshold_ms
	should_log = should_log or cells_erased >= destructive_operation_threshold
	should_log = should_log or nodes_freed >= destructive_operation_threshold
	if not should_log:
		return

	var line := "[CHUNK] source=%s action=%s chunk=%s ms=%.2f cells_set=%d cells_erased=%d nodes_spawned=%d nodes_freed=%d revalidated_removed=%d kind=%s steps=%d attempts=%d expensive_checks=%d checks_ms=%.2f large_structure_candidates=%d large_structure_rejected=%d large_structure_checks_ms=%.2f instantiate_ms=%.2f add_child_ms=%.2f register_ms=%.2f overlap_ms=%.2f pending_load=%d pending_unload=%d loaded=%d" % [
		source_name,
		action,
		str(chunk),
		elapsed_ms,
		int(stats.get("cells_set", 0)),
		cells_erased,
		int(stats.get("nodes_spawned", 0)),
		nodes_freed,
		int(stats.get("revalidated_removed", 0)),
		str(stats.get("generation_kind", "")),
		int(stats.get("scheduler_steps", 0)),
		int(stats.get("spawn_attempts", 0)),
		int(stats.get("expensive_checks", 0)),
		float(stats.get("spawn_checks_usec", 0)) / 1000.0,
		int(stats.get("large_structure_candidates", 0)),
		int(stats.get("large_structure_rejected", 0)),
		float(stats.get("large_structure_checks_usec", 0)) / 1000.0,
		float(stats.get("instantiate_usec", 0)) / 1000.0,
		float(stats.get("add_child_usec", 0)) / 1000.0,
		float(stats.get("register_usec", 0)) / 1000.0,
		float(stats.get("overlap_clear_usec", 0)) / 1000.0,
		int(stats.get("pending_load", 0)),
		int(stats.get("pending_unload", 0)),
		int(stats.get("loaded_chunks", 0))
	]
	_emit_log(line)


func _emit_log(text: String) -> void:
	if mirror_to_console:
		print(text)
	var monitor := get_node_or_null("/root/StutterMonitor")
	if monitor != null and monitor.has_method("append_log_file_only"):
		monitor.call("append_log_file_only", text)
	elif monitor != null and monitor.has_method("_log_line"):
		monitor.call("_log_line", text)
