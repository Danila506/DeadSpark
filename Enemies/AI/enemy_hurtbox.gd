extends Area2D
class_name EnemyHurtbox

const DamageZones = preload("res://Enemies/AI/damage_zones.gd")

@export_enum("head", "body", "legs") var damage_zone: String = "body"


func _ready() -> void:
	monitoring = false
	monitorable = true
	collision_layer = DamageZones.HURTBOX_COLLISION_LAYER
	collision_mask = 0
	add_to_group(&"damage_hitbox")
	set_meta(&"damage_zone", damage_zone)
