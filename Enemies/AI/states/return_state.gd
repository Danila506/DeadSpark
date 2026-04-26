extends EnemyState
class_name EnemyReturnState

var _return_point: Vector2 = Vector2.ZERO


func _ready() -> void:
	state_name = EnemyAI.STATE_RETURN
	min_time_in_state = 0.1


func enter(_data: Dictionary = {}) -> void:
	_return_point = enemy.get_return_position()
	enemy.move_to(_return_point, enemy.config.patrol_speed)
	enemy.request_animation(&"walk")


func physics_update(_delta: float) -> void:
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

	if enemy.is_close_to(_return_point, enemy.config.return_arrive_distance):
		if enemy.has_patrol_points():
			transition(EnemyAI.STATE_PATROL)
		else:
			transition(EnemyAI.STATE_IDLE)
		return
