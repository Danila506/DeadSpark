extends EnemyState
class_name EnemyIdleState

var _wait_left: float = 0.0


func _ready() -> void:
	state_name = EnemyAI.STATE_IDLE
	min_time_in_state = 0.1


func enter(_data: Dictionary = {}) -> void:
	_wait_left = randf_range(enemy.config.idle_wait_min_sec, enemy.config.idle_wait_max_sec)
	enemy.stop_move()
	enemy.request_animation(&"idle")


func physics_update(delta: float) -> void:
	if enemy.should_start_house_search():
		transition(EnemyAI.STATE_HOUSE_SEARCH, enemy.build_house_search_enter_data())
		return

	if enemy.should_chase_target():
		transition(EnemyAI.STATE_CHASE)
		return

	if enemy.has_pending_noise():
		var noise_position: Vector2 = enemy.consume_pending_noise()
		transition(EnemyAI.STATE_SUSPICIOUS, {"point": noise_position})
		return

	_wait_left -= delta
	if _wait_left > 0.0:
		return

	if enemy.has_patrol_points():
		transition(EnemyAI.STATE_PATROL)
	else:
		_wait_left = randf_range(enemy.config.idle_wait_min_sec, enemy.config.idle_wait_max_sec)
