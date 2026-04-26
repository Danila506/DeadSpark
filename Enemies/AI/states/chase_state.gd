extends EnemyState
class_name EnemyChaseState

func _ready() -> void:
	state_name = EnemyAI.STATE_CHASE
	min_time_in_state = 0.05


func enter(_data: Dictionary = {}) -> void:
	enemy.request_animation(&"run")


func physics_update(_delta: float) -> void:
	if enemy.should_start_house_search():
		transition(EnemyAI.STATE_HOUSE_SEARCH, enemy.build_house_search_enter_data())
		return

	if not enemy.should_chase_target():
		if enemy.has_last_known_target_position():
			transition(EnemyAI.STATE_SEARCH, {"point": enemy.get_last_known_target_position()})
		else:
			transition(EnemyAI.STATE_RETURN)
		return

	if enemy.can_attack_target():
		transition(EnemyAI.STATE_ATTACK)
		return

	enemy.move_to(enemy.get_chase_destination(), enemy.config.chase_speed)
	enemy.request_animation(&"run")
