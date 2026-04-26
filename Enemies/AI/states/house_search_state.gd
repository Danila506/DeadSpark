extends EnemyState
class_name EnemyHouseSearchState


func _ready() -> void:
	state_name = EnemyAI.STATE_HOUSE_SEARCH
	min_time_in_state = 0.15


func enter(data: Dictionary = {}) -> void:
	enemy.begin_house_search(data)
	enemy.request_animation(&"walk")


func physics_update(delta: float) -> void:
	if enemy.should_chase_target() and not enemy.is_target_inside_house():
		transition(EnemyAI.STATE_CHASE)
		return

	var next_state: StringName = enemy.update_house_search(delta)
	if next_state != StringName(""):
		transition(next_state)
