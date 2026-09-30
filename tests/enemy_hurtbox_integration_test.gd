extends Node2D

const BANDIT_SCENE := preload("res://Enemies/Bandits/Bandit_1/Bandit.tscn")
const PROJECTILE_SCENE := preload("res://Projectile/projectile.tscn")
const DamageZones := preload("res://Enemies/AI/damage_zones.gd")
const COMBAT_ACTOR_SCENES: Array[PackedScene] = [
	preload("res://Enemies/Bandits/Bandit_1/Bandit.tscn"),
	preload("res://Enemies/Bandits/Bandit_2/Bandit_2.tscn"),
	preload("res://Enemies/Bandits/Bandit_3/Bandit_3.tscn"),
	preload("res://Enemies/Bandits/Bandit_4/Bandit_4.tscn"),
	preload("res://Enemies/Wolf/wolf.tscn"),
	preload("res://Animals/Deer/Deer.tscn"),
]


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("Enemy hurtbox integration: " + message)
	get_tree().quit(1)


func _run() -> void:
	for actor_scene in COMBAT_ACTOR_SCENES:
		var actor := actor_scene.instantiate()
		var actor_hurtbox := actor.get_node_or_null("Hurtbox") as Area2D
		_check(actor_hurtbox != null, "%s must provide the shared Hurtbox component" % actor.name)
		_check(actor_hurtbox.collision_layer == DamageZones.HURTBOX_COLLISION_LAYER, "%s Hurtbox uses the wrong layer" % actor.name)
		_check(actor_hurtbox.collision_mask == 0, "%s Hurtbox must not affect movement" % actor.name)
		actor.free()

	var enemy := BANDIT_SCENE.instantiate() as CharacterBody2D
	enemy.global_position = Vector2(180.0, 100.0)
	add_child(enemy)
	await get_tree().physics_frame

	var feet_shape := enemy.get_node("CollisionShape2D") as CollisionShape2D
	var original_feet_position := feet_shape.position
	var original_feet_scale := feet_shape.scale
	var original_enemy_layer := enemy.collision_layer
	var original_enemy_mask := enemy.collision_mask
	var hurtbox := enemy.get_node("Hurtbox") as Area2D
	var hurtbox_shape := hurtbox.get_node("CollisionShape2D") as CollisionShape2D

	_check(hurtbox != null and hurtbox_shape != null and hurtbox_shape.shape != null, "Hurtbox must contain a collision shape")
	_check(hurtbox.collision_layer == DamageZones.HURTBOX_COLLISION_LAYER, "Hurtbox must use the dedicated damage layer")
	_check(hurtbox.collision_mask == 0, "Hurtbox must not collide with movement bodies")
	_check(not hurtbox.monitoring and hurtbox.monitorable, "Hurtbox must only be queryable by projectiles")
	_check(hurtbox.is_in_group(&"damage_hitbox"), "Hurtbox must use the existing damage-hitbox contract")

	var initial_health: float = enemy.health
	var shooter := Node2D.new()
	shooter.global_position = Vector2(20.0, 80.0)
	add_child(shooter)
	var projectile := PROJECTILE_SCENE.instantiate()
	add_child(projectile)
	projectile.initialize(
		shooter.global_position,
		Vector2.RIGHT,
		1200.0,
		1.0,
		2,
		1,
		20.0,
		300.0,
		shooter
	)

	for _frame in range(30):
		await get_tree().physics_frame
		if enemy.health < initial_health:
			break

	_check(enemy.health < initial_health, "A projectile above the feet collider must damage the enemy through Hurtbox")
	_check(feet_shape.position == original_feet_position, "Hurtbox setup changed the feet collider position")
	_check(feet_shape.scale == original_feet_scale, "Hurtbox setup changed the feet collider scale")
	_check(enemy.collision_layer == original_enemy_layer, "Hurtbox setup changed the enemy physics layer")
	_check(enemy.collision_mask == original_enemy_mask, "Hurtbox setup changed the enemy movement mask")

	print("ENEMY_HURTBOX_INTEGRATION_TEST=PASS")
	get_tree().quit(0)
