@tool
class_name WorldGenStableIdAssignment
extends RefCounted

static func assign_missing(root: Node) -> int:
	if root == null:
		return 0
	return _assign_recursive(root)

static func _assign_recursive(node: Node) -> int:
	var assigned := 0
	if _is_structural(node) and String(node.get_meta("stable_id", "")).is_empty():
		node.set_meta("stable_id", _new_stable_id())
		assigned += 1
	for child in node.get_children():
		assigned += _assign_recursive(child)
	return assigned

static func _is_structural(node: Node) -> bool:
	return node is Marker2D or node is VillageSpawnGroup

static func _new_stable_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "m_%08x%08x" % [rng.randi(), rng.randi()]
