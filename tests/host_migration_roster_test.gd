extends Node

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var manager: Node = load("res://Autoloads/NetworkManager.gd").new()
	add_child(manager)
	manager.call("_on_peer_connected", 12)
	manager.call("_on_peer_connected", 7)
	manager.call("_on_peer_connected", 9)
	_check(int(manager.call("_elect_host_migration_peer_id", 12)) == 7, "lowest connected client should be elected")
	manager.call("_on_peer_disconnected", 7)
	_check(int(manager.call("_elect_host_migration_peer_id", 12)) == 9, "disconnected client must not remain eligible")
	manager.call("_on_peer_disconnected", 9)
	_check(int(manager.call("_elect_host_migration_peer_id", 12)) == 12, "local connected client should remain eligible")
	for failure in failures:
		push_error(failure)
	print("HOST_MIGRATION_ROSTER_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
