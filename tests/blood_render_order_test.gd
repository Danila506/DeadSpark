extends Node

const BANDIT_SCENE := preload("res://Enemies/Bandits/Bandit_1/Bandit.tscn")
const PLAYER_SCENE := preload("res://Player/player.tscn")
const GUI_SCENE := preload("res://gui/GUI.tscn")
const BloodRenderOrder := preload("res://Effects/blood_render_order.gd")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _snapshot_child_ids() -> Dictionary:
	var result: Dictionary = {}
	for child in get_children():
		result[child.get_instance_id()] = true
	return result


func _find_new_top_level_animated_sprite(previous_ids: Dictionary) -> AnimatedSprite2D:
	for child in get_children():
		if child is AnimatedSprite2D and not previous_ids.has(child.get_instance_id()):
			var sprite := child as AnimatedSprite2D
			if sprite.top_level:
				return sprite
	return null


func _run() -> void:
	var gui := GUI_SCENE.instantiate()
	gui.name = "UI"
	add_child(gui)
	var players := Node2D.new()
	players.name = "Players"
	add_child(players)
	var player := PLAYER_SCENE.instantiate()
	players.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)

	var bandit := BANDIT_SCENE.instantiate()
	add_child(bandit)
	bandit.set_process(false)
	bandit.set_physics_process(false)
	var source := Node2D.new()
	source.position = Vector2.LEFT * 20.0
	add_child(source)
	await get_tree().process_frame

	var before_bandit_blood := _snapshot_child_ids()
	bandit._spawn_hit_blood(source)
	var bandit_blood := _find_new_top_level_animated_sprite(before_bandit_blood)
	_check(bandit_blood != null, "bandit hit blood effect was not spawned")
	if bandit_blood != null:
		_check(not bandit_blood.z_as_relative, "bandit blood must use an absolute render layer")
		_check(bandit_blood.z_index <= BloodRenderOrder.BLOOD_EFFECT_MAX_Z_INDEX, "bandit blood is above the blood layer")
		_check(bandit_blood.z_index < bandit.body_sprite.z_index, "bandit blood overlaps the living body")

	bandit.kill()
	_check(bandit.body_sprite.z_index >= BloodRenderOrder.ACTOR_MIN_Z_INDEX, "dead bandit body is not above blood")
	_check(bandit_blood == null or bandit_blood.z_index < bandit.body_sprite.z_index, "bandit blood overlaps the corpse")
	if bandit.dying_sprite != null:
		_check(bandit.dying_sprite.z_index >= BloodRenderOrder.ACTOR_MIN_Z_INDEX, "dead bandit interaction sprite is not above blood")

	var before_player_blood := _snapshot_child_ids()
	player.blood_effects_controller.spawn_hit_blood(source, {})
	var player_blood := _find_new_top_level_animated_sprite(before_player_blood)
	var player_body := player.get_node("BodySprite") as AnimatedSprite2D
	_check(player_blood != null, "player hit blood effect was not spawned")
	if player_blood != null:
		_check(not player_blood.z_as_relative, "player blood must use an absolute render layer")
		_check(player_blood.z_index <= BloodRenderOrder.BLOOD_EFFECT_MAX_Z_INDEX, "player blood is above the blood layer")
		_check(player_blood.z_index < player_body.z_index, "player blood overlaps the player body")

	for failure in failures:
		push_error("Blood render order: " + failure)
	print("BLOOD_RENDER_ORDER_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
