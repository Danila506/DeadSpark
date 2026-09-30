extends Node2D

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var player_source: String = FileAccess.get_file_as_string("res://Player/player.gd")
	check(not player_source.contains("rpc_submit_state"), "client position RPC must not exist")
	check(not player_source.contains("_apply_server_received_state"), "server must not apply client positions")

	var gui = preload("res://gui/GUI.tscn").instantiate()
	gui.name = "UI"
	add_child(gui)
	var players := Node2D.new()
	players.name = "Players"
	add_child(players)
	var actor = preload("res://Player/player.tscn").instantiate()
	actor.set_physics_process(false)
	players.add_child(actor)
	actor.global_position = Vector2.ZERO

	var wall := StaticBody2D.new()
	wall.global_position = Vector2(24.0, 0.0)
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8.0, 100.0)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	add_child(wall)

	await get_tree().physics_frame
	check(actor._sanitize_network_input(Vector2(50.0, 0.0)).is_equal_approx(Vector2.RIGHT), "input magnitude must be clamped")
	check(actor._sanitize_network_input(Vector2(NAN, 0.0)) == Vector2.ZERO, "non-finite input must be rejected")

	var live_peer := CharacterBody2D.new()
	live_peer.add_to_group("player")
	players.add_child(live_peer)
	actor.add_collision_exception_with(live_peer)
	var excluded_rids: Array[RID] = actor.movement_controller._get_excluded_body_rids()
	check(excluded_rids.has(live_peer.get_rid()), "live non-blocking peer must be excluded from overlap recovery")
	actor.remove_collision_exception_with(live_peer)
	live_peer.queue_free()
	await get_tree().process_frame
	check(
		actor.movement_controller._get_excluded_body_rids().size() >= 1,
		"freed LAN collision peers must not break overlap exclusions"
	)

	var now_ms: int = Time.get_ticks_msec()
	actor._net_server_last_input_recv_ms = now_ms
	actor._net_input_vector = Vector2.ZERO
	check(
		actor._resolve_server_remote_input(now_ms) == Vector2.ZERO,
		"a fresh zero input must stop remote movement instead of reusing the previous direction"
	)
	actor._net_input_vector = Vector2.RIGHT
	actor._net_server_last_input_recv_ms = now_ms - actor.NET_SERVER_INPUT_STALE_TIMEOUT_MS - 1
	check(
		actor._resolve_server_remote_input(now_ms) == Vector2.ZERO,
		"stale remote input must stop movement after packet loss"
	)
	check(actor._net_input_vector == Vector2.ZERO, "stale remote input must clear the stored direction")

	for _step in range(30):
		actor._apply_network_movement(1.0 / 60.0, Vector2.RIGHT)
		await get_tree().physics_frame
	check(actor.global_position.x < wall.global_position.x, "authoritative movement must collide with walls")

	for failure in failures:
		push_error(failure)
	print("LAN_MOVEMENT_AUTHORITY_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
