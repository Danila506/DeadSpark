extends Node


class ProgressingSource extends Node:
	var remaining_steps := 12

	func has_generation_pending() -> bool:
		return remaining_steps > 0

	func force_generate_step(_budget: int) -> void:
		remaining_steps -= 1

	func get_pending_generation_chunk_count() -> int:
		return maxi(0, remaining_steps)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var orchestrator := WorldGenerationOrchestrator.new()
	add_child(orchestrator)
	var source := ProgressingSource.new()
	orchestrator.add_child(source)
	var sources: Array[Node] = [source]
	var error := await orchestrator._drain_incremental_phase("test_phase", sources, 1, 3)
	if not error.is_empty():
		printerr("Progress-aware phase drain failed: %s" % error)
		get_tree().quit(1)
		return
	if source.remaining_steps > 0:
		printerr("Progress-aware phase drain stopped before the source completed")
		get_tree().quit(1)
		return
	print("World generation phase progress test passed: total work may exceed the stall-frame limit")
	get_tree().quit(0)
