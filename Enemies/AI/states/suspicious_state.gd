extends EnemyState
class_name EnemySuspiciousState

var _investigate_point: Vector2 = Vector2.ZERO
var _time_left: float = 0.0


func _ready() -> void:
	state_name = EnemyAI.STATE_SUSPICIOUS
	min_time_in_state = 0.15


func enter(data: Dictionary = {}) -> void:
	_time_left = enemy.config.suspicious_duration_sec
	_investigate_point = data.get("point", enemy.global_position)
	enemy.move_to(_investigate_point, enemy.config.search_speed)
	enemy.request_animation(&"walk")


func physics_update(delta: float) -> void:
	if enemy.should_start_house_search():
		transition(EnemyAI.STATE_HOUSE_SEARCH, enemy.build_house_search_enter_data())
		return

	if enemy.should_chase_target():
		transition(EnemyAI.STATE_CHASE)
		return

	_time_left -= delta
	if enemy.is_close_to(_investigate_point, enemy.config.investigate_arrive_distance) or _time_left <= 0.0:
		transition(EnemyAI.STATE_SEARCH, {"point": _investigate_point})
		return
