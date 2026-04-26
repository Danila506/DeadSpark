extends EnemyState
class_name EnemyPatrolState

var _wait_left: float = 0.0


func _ready() -> void:
	state_name = EnemyAI.STATE_PATROL
	min_time_in_state = 0.2


func enter(_data: Dictionary = {}) -> void:
	_wait_left = 0.0
	if not enemy.has_patrol_points():
		transition(EnemyAI.STATE_IDLE)
		return
	_go_to_current_patrol_point()


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

	var target_point: Vector2 = enemy.get_patrol_point(enemy.get_patrol_index())
	if enemy.is_close_to(target_point, enemy.config.patrol_arrive_distance):
		if _wait_left <= 0.0:
			enemy.stop_move()
			enemy.request_animation(&"idle")
			_wait_left = randf_range(enemy.config.patrol_wait_min_sec, enemy.config.patrol_wait_max_sec)
			return

		_wait_left -= delta
		if _wait_left <= 0.0:
			enemy.advance_patrol_index()
			_go_to_current_patrol_point()
		return

	enemy.request_animation(&"walk")


func _go_to_current_patrol_point() -> void:
	var next_point: Vector2 = enemy.get_patrol_point(enemy.get_patrol_index())
	enemy.move_to(next_point, enemy.config.patrol_speed)
	enemy.request_animation(&"walk")
