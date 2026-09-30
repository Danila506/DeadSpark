extends Node

const LAN_MAP := preload("res://LanMap.tscn")

var failures: Array[String] = []


func _ready() -> void:
	var map := LAN_MAP.instantiate()
	var y_sort_root := map.get_node_or_null("Y-Sort_Objects") as Node2D
	var player := map.get_node_or_null("Y-Sort_Objects/Player2") as Node2D
	var bandit_base := map.get_node_or_null("Y-Sort_Objects/BanditBase") as Node2D
	_check(y_sort_root != null and y_sort_root.y_sort_enabled, "LAN Y-sort root missing or disabled")
	_check(player != null, "LAN player is outside the Y-sort root")
	_check(bandit_base != null, "LAN bandit base is outside the player Y-sort root")
	if bandit_base != null:
		_check(bandit_base.y_sort_enabled, "bandit base nested Y-sort is disabled")
		var sort_root := bandit_base.get_node_or_null("BonfireSortRoot") as Node2D
		_check(sort_root != null and sort_root.position.y == 12.0, "bonfire sorting root is not at the coal bed")
		var bonfire := bandit_base.get_node_or_null("BonfireSortRoot/Bonfire") as AnimatedSprite2D
		_check(bonfire != null, "bandit base bonfire missing")
		if bonfire != null:
			_check(bonfire.z_index == 0, "bonfire uses a fixed Z layer")
			_check(bonfire.position.y == -12.0, "bonfire visual position shifted")
	map.free()
	for failure in failures:
		push_error(failure)
	print("LAN_BANDIT_BASE_SORTING_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
