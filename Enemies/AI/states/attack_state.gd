extends EnemyState
class_name EnemyAttackState

var _windup_left: float = 0.0


func _ready() -> void:
	state_name = EnemyAI.STATE_ATTACK
	min_time_in_state = 0.1


func enter(_data: Dictionary = {}) -> void:
	_windup_left = enemy.config.attack_windup_sec
	enemy.stop_move()
	enemy.request_animation(&"attack")


func physics_update(delta: float) -> void:
	if not enemy.should_chase_target():
		if enemy.has_last_known_target_position():
			transition(EnemyAI.STATE_SEARCH, {"point": enemy.get_last_known_target_position()})
		else:
			transition(EnemyAI.STATE_RETURN)
		return

	if enemy.should_start_house_search():
		transition(EnemyAI.STATE_HOUSE_SEARCH, enemy.build_house_search_enter_data())
		return

	enemy.stop_move()
	enemy.face_towards(enemy.get_target_position())

	if enemy.should_leave_attack():
		transition(EnemyAI.STATE_CHASE)
		return

	_windup_left -= delta
	if _windup_left > 0.0:
		return

	if enemy.perform_attack():
		if enemy.is_ranged_enemy():
			_windup_left = 0.0
		else:
			# Новый удар только после глобального cooldown в Enemy.
			_windup_left = enemy.config.attack_cooldown_sec
