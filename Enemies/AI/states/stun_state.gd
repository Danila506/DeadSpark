extends EnemyState
class_name EnemyStunState

var _stun_left: float = 0.0


func _ready() -> void:
	state_name = EnemyAI.STATE_STUN
	min_time_in_state = 0.05


func enter(data: Dictionary = {}) -> void:
	_stun_left = data.get("duration_sec", enemy.config.stun_default_duration_sec)
	enemy.stop_move()
	enemy.request_animation(&"hurt")


func physics_update(delta: float) -> void:
	enemy.stop_move()
	_stun_left -= delta
	if _stun_left > 0.0:
		return

	if enemy.should_chase_target():
		transition(EnemyAI.STATE_CHASE)
	elif enemy.has_patrol_points():
		transition(EnemyAI.STATE_RETURN)
	else:
		transition(EnemyAI.STATE_IDLE)
