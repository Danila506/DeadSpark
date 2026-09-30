extends Node2D

const BANDIT_SCENE := preload("res://Enemies/Bandits/Bandit_4/Bandit_4.tscn")
const PLAYER_SCENE := preload("res://Player/player.tscn")
const DamageZones := preload("res://Enemies/AI/damage_zones.gd")
const BANDIT_SCENES: Array[PackedScene] = [
	preload("res://Enemies/Bandits/Bandit_1/Bandit.tscn"),
	preload("res://Enemies/Bandits/Bandit_2/Bandit_2.tscn"),
	preload("res://Enemies/Bandits/Bandit_3/Bandit_3.tscn"),
	preload("res://Enemies/Bandits/Bandit_4/Bandit_4.tscn"),
]


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("Bandit projectile/player integration: " + message)
	get_tree().quit(1)


func _run() -> void:
	for bandit_scene in BANDIT_SCENES:
		var bandit_variant := bandit_scene.instantiate()
		_check(bandit_variant.role_group == &"bandit", "%s must declare its bandit faction explicitly" % bandit_variant.name)
		bandit_variant.free()

	var ui := Control.new()
	ui.name = "UI"
	get_tree().root.add_child(ui)
	var inventory_root := Control.new()
	inventory_root.name = "InventoryRoot"
	ui.add_child(inventory_root)

	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	player.global_position = Vector2(220.0, 120.0)
	add_child(player)
	player.set_process(false)
	player.set_physics_process(false)

	var bandit := BANDIT_SCENE.instantiate() as CharacterBody2D
	bandit.config = bandit.config.duplicate(true)
	bandit.config.ranged_spread_degrees = 0.0
	bandit.config.projectile_damage = 20.0
	bandit.global_position = Vector2(40.0, 120.0)
	add_child(bandit)
	bandit.set_physics_process(false)

	var friendly_bandit := BANDIT_SCENE.instantiate() as CharacterBody2D
	friendly_bandit.global_position = Vector2(130.0, 220.0)
	add_child(friendly_bandit)
	friendly_bandit.set_process(false)
	friendly_bandit.set_physics_process(false)
	await get_tree().physics_frame

	var hurtbox := player.get_node_or_null("Hurtbox") as Area2D
	_check(hurtbox != null, "Player must provide the shared Hurtbox component")
	_check(hurtbox.collision_layer == DamageZones.HURTBOX_COLLISION_LAYER, "Player Hurtbox uses the wrong layer")
	_check(hurtbox.collision_mask == 0, "Player Hurtbox must not affect movement")
	_check(not hurtbox.monitoring and hurtbox.monitorable, "Player Hurtbox must only be queryable by projectiles")
	_check(hurtbox.is_in_group(&"damage_hitbox"), "Player Hurtbox must use the damage-hitbox contract")

	bandit.current_target = player
	var aim_position: Vector2 = bandit._resolve_ranged_target_position(player)
	_check(aim_position.is_equal_approx(hurtbox.global_position), "Bandit must aim at the Player Hurtbox instead of the feet origin")
	_check(aim_position.y < player.global_position.y, "Bandit aim point must be above the Player feet origin")
	_check(bandit._has_attack_line_of_sight(), "Player Hurtbox must count as a clear hit on the intended target")

	friendly_bandit.global_position = Vector2(130.0, 120.0)
	await get_tree().physics_frame
	_check(bandit._would_ranged_attack_hit_ally(), "Bandit AI must detect another bandit in the firing line")

	var initial_health: float = player.health
	var friendly_initial_health: float = friendly_bandit.health
	bandit._fire_ranged_projectile()
	for _frame in range(30):
		await get_tree().physics_frame
		if player.health < initial_health:
			break

	_check(is_equal_approx(friendly_bandit.health, friendly_initial_health), "Bandit projectile must not damage another bandit")
	_check(player.health < initial_health, "Bandit projectile must damage the Player through Hurtbox")
	print("BANDIT_PROJECTILE_PLAYER_INTEGRATION_TEST=PASS")
	get_tree().quit(0)
