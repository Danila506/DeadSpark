extends Node

@export_range(1, 256, 1) var max_nodes_per_frame: int = 24
@export_range(0.25, 8.0, 0.25) var frame_budget_ms: float = 1.5

var _pending_nodes: Array[Node] = []
var _total_enqueued: int = 0
var _total_freed: int = 0
var _scene_transition_active: bool = false
var _total_direct_freed: int = 0


func _ready() -> void:
	set_process(true)
	if not get_tree().scene_changed.is_connected(_on_scene_changed):
		get_tree().scene_changed.connect(_on_scene_changed)


func _process(_delta: float) -> void:
	if _pending_nodes.is_empty():
		return

	var processed := 0
	var start_usec := Time.get_ticks_usec()
	var budget_usec := int(maxf(frame_budget_ms, 0.25) * 1000.0)

	while processed < max_nodes_per_frame and not _pending_nodes.is_empty():
		if Time.get_ticks_usec() - start_usec >= budget_usec:
			break
		var node: Node = _pending_nodes.pop_front()
		if node == null or not is_instance_valid(node):
			continue
		node.queue_free()
		processed += 1
		_total_freed += 1


func enqueue(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _scene_transition_active:
		node.queue_free()
		_total_enqueued += 1
		_total_freed += 1
		_total_direct_freed += 1
		return
	if node.get_parent() != self:
		if node is CanvasItem:
			(node as CanvasItem).visible = false
		if node is Node2D:
			(node as Node2D).process_mode = Node.PROCESS_MODE_DISABLED
		node.reparent(self, false)
	if not _pending_nodes.has(node):
		_pending_nodes.append(node)
		_total_enqueued += 1


func begin_scene_transition() -> void:
	_scene_transition_active = true
	_flush_pending_nodes_direct()


func is_scene_transition_active() -> bool:
	return _scene_transition_active


func _on_scene_changed() -> void:
	_scene_transition_active = false


func _flush_pending_nodes_direct() -> void:
	if _pending_nodes.is_empty():
		return
	for node in _pending_nodes:
		if node == null or not is_instance_valid(node):
			continue
		node.queue_free()
		_total_freed += 1
		_total_direct_freed += 1
	_pending_nodes.clear()


func get_debug_info() -> Dictionary:
	return {
		"pending": _pending_nodes.size(),
		"total_enqueued": _total_enqueued,
		"total_freed": _total_freed,
		"total_direct_freed": _total_direct_freed,
		"scene_transition_active": _scene_transition_active
	}
