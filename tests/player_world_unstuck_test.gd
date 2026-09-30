extends Node2D

const BUSH_SCENE := preload("res://World/Assets/Biom1/Bush.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := CharacterBody2D.new()
	player.collision_layer = 1
	player.collision_mask = 1
	var player_shape := CollisionShape2D.new()
	player_shape.name = "CollisionShape2D"
	var player_circle := CircleShape2D.new()
	player_circle.radius = 5.0
	player_shape.shape = player_circle
	player.add_child(player_shape)
	add_child(player)

	var controller := PlayerMovementController.new(player)
	player.global_position = Vector2(-80.0, 0.0)
	await get_tree().physics_frame
	_check(not controller.resolve_world_overlap(), "clear position must not trigger recovery")

	var bush := BUSH_SCENE.instantiate()
	add_child(bush)
	var bush_collider := bush.get_node("StaticBody2D/CollisionShape2D") as CollisionShape2D
	player.global_position = bush_collider.global_position
	player.force_update_transform()
	await get_tree().physics_frame
	var bush_recovered := controller.resolve_world_overlap()
	_check(bush_recovered, "player embedded in a bush collider must be recovered")
	_check(controller._is_position_clear(player.global_position), "bush recovery must end at a collision-free point")

	var blocker := StaticBody2D.new()
	blocker.collision_layer = 1
	blocker.collision_mask = 1
	var blocker_shape := CollisionShape2D.new()
	var blocker_rectangle := RectangleShape2D.new()
	blocker_rectangle.size = Vector2(160.0, 160.0)
	blocker_shape.shape = blocker_rectangle
	blocker.add_child(blocker_shape)
	add_child(blocker)

	player.global_position = Vector2(-120.0, 0.0)
	player.force_update_transform()
	await get_tree().physics_frame
	_check(not controller.resolve_world_overlap(), "new clear position must become the safe fallback")
	player.global_position = Vector2.ZERO
	player.force_update_transform()
	await get_tree().physics_frame
	var fallback_recovered := controller.resolve_world_overlap()
	_check(fallback_recovered, "deep overlap must recover to the last safe position")
	_check(player.global_position.is_equal_approx(Vector2(-120.0, 0.0)), "deep overlap must use the last confirmed safe position")
	_check(controller._is_position_clear(player.global_position), "fallback recovery must be collision-free")

	player.global_position = Vector2(85.5, 0.0)
	player.force_update_transform()
	await get_tree().physics_frame
	var touching_position := player.global_position
	_check(not controller.resolve_world_overlap(), "standing next to a collider must not trigger recovery")
	_check(player.global_position.is_equal_approx(touching_position), "normal wall contact must not teleport the player")

	if not _failures.is_empty():
		for failure in _failures:
			push_error("Player world unstuck: " + failure)
		get_tree().quit(1)
		return
	print("PLAYER_WORLD_UNSTUCK_TEST=PASS")
	get_tree().quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
