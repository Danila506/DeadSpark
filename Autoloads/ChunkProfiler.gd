extends Node

@export var enabled: bool = false
@export var log_all_operations: bool = false
@export var spike_threshold_ms: float = 8.0
@export var destructive_operation_threshold: int = 9999


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

	print(
		"[CHUNK] source=", source_name,
		" action=", action,
		" chunk=", chunk,
		" ms=", snappedf(elapsed_ms, 0.01),
		" cells_set=", int(stats.get("cells_set", 0)),
		" cells_erased=", cells_erased,
		" nodes_spawned=", int(stats.get("nodes_spawned", 0)),
		" nodes_freed=", nodes_freed,
		" revalidated_removed=", int(stats.get("revalidated_removed", 0)),
		" pending_load=", int(stats.get("pending_load", 0)),
		" pending_unload=", int(stats.get("pending_unload", 0)),
		" loaded=", int(stats.get("loaded_chunks", 0))
	)
