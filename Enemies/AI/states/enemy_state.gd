extends Node
class_name EnemyState

@export var state_name: StringName
@export var min_time_in_state: float = 0.0

var enemy: EnemyAI = null
var machine: EnemyStateMachine = null


func set_context(enemy_ref: EnemyAI, machine_ref: EnemyStateMachine) -> void:
	enemy = enemy_ref
	machine = machine_ref


func enter(_data: Dictionary = {}) -> void:
	pass


func exit() -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func transition(next_state: StringName, data: Dictionary = {}, force: bool = false) -> bool:
	if machine == null:
		return false
	return machine.change_state(next_state, data, force)

