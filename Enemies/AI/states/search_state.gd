extends EnemyState
class_name EnemySearchState

var _search_point: Vector2 = Vector2.ZERO
var _inspect_left: float = 0.0
var _arrived: bool = false


func _ready() -> void:
	state_name = EnemyAI.STATE_SEARCH
	min_time_in_state = 0.15


func enter(data: Dictionary = {}) -> void:
	_search_point = data.get("point", enemy.get_last_known_target_position())
	_arrived = false
	_inspect_left = enemy.config.search_duration_sec
	enemy.move_to(_search_point, enemy.config.search_speed)
	enemy.request_animation(&"walk")


func physics_update(delta: float) -> void:
	if enemy.should_start_house_search():
		transition(EnemyAI.STATE_HOUSE_SEARCH, enemy.build_house_search_enter_data())
		return

	if enemy.should_chase_target():
		transition(EnemyAI.STATE_CHASE)
		return

	if enemy.has_pending_noise():
		_search_point = enemy.consume_pending_noise()
		_arrived = false
		_inspect_left = enemy.config.search_duration_sec
		enemy.move_to(_search_point, enemy.config.search_speed)
		enemy.request_animation(&"walk")
		return

	if not _arrived:
		if enemy.is_close_to(_search_point, enemy.config.investigate_arrive_distance):
			_arrived = true
			enemy.stop_move()
			enemy.request_animation(&"idle")
		return

	_inspect_left -= delta
	if _inspect_left > 0.0:
		return

	if enemy.has_patrol_points():
		transition(EnemyAI.STATE_RETURN)
	else:
		transition(EnemyAI.STATE_IDLE)
