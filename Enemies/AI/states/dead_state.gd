extends EnemyState
class_name EnemyDeadState


func _ready() -> void:
	state_name = EnemyAI.STATE_DEAD
	min_time_in_state = 0.0


func enter(_data: Dictionary = {}) -> void:
	enemy.stop_move()
	enemy.request_animation(&"death")


func physics_update(_delta: float) -> void:
	enemy.stop_move()
