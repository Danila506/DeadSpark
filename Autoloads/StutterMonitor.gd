extends Node

@export var enabled: bool = false
@export var spike_threshold_ms: float = 30.0
@export var log_cooldown_sec: float = 0.5

var _cooldown_left: float = 0.0


func _process(delta: float) -> void:
	if not enabled:
		return

	_cooldown_left = max(_cooldown_left - delta, 0.0)
	var frame_ms: float = delta * 1000.0
	if frame_ms < spike_threshold_ms or _cooldown_left > 0.0:
		return

	_cooldown_left = max(log_cooldown_sec, 0.0)
	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var object_count: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphan_node_count: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	print(
		"[STUTTER] frame=", snappedf(frame_ms, 0.01),
		"ms fps=", Engine.get_frames_per_second(),
		" process=", snappedf(process_ms, 0.01),
		"ms physics=", snappedf(physics_ms, 0.01),
		"ms objects=", object_count,
		" nodes=", node_count,
		" orphan_nodes=", orphan_node_count
	)
