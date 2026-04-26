extends Node
class_name EnemyStateMachine

signal state_changed(from_state: StringName, to_state: StringName)

@export var initial_state: StringName = &"IDLE"

var _states: Dictionary = {}
var _current_state: EnemyState = null
var _current_name: StringName = &""
var _state_elapsed_sec: float = 0.0
var _enemy: EnemyAI = null
var _transition_cooldown_left: float = 0.0


func setup(enemy: EnemyAI) -> void:
	_enemy = enemy
	_collect_states()
	_enter_initial_state()


func physics_update(delta: float) -> void:
	if _current_state == null:
		return
	_state_elapsed_sec += delta
	_transition_cooldown_left = max(_transition_cooldown_left - delta, 0.0)
	_current_state.physics_update(delta)


func change_state(next_state: StringName, data: Dictionary = {}, force: bool = false) -> bool:
	var next: EnemyState = _states.get(next_state, null)
	if next == null:
		return false

	if _current_name == next_state and not force:
		return false

	if not force:
		if _transition_cooldown_left > 0.0:
			return false
		if _current_state != null and _state_elapsed_sec < _current_state.min_time_in_state:
			return false

	var previous_name: StringName = _current_name
	if _current_state != null:
		_current_state.exit()

	_current_state = next
	_current_name = next_state
	_state_elapsed_sec = 0.0
	_transition_cooldown_left = _enemy.config.transition_cooldown_sec if _enemy != null and _enemy.config != null else 0.0
	_current_state.enter(data)
	state_changed.emit(previous_name, _current_name)
	return true


func get_current_state_name() -> StringName:
	return _current_name


func get_state_elapsed() -> float:
	return _state_elapsed_sec


func _collect_states() -> void:
	_states.clear()
	for child in get_children():
		if child is EnemyState:
			var state: EnemyState = child as EnemyState
			state.set_context(_enemy, self)
			_states[state.state_name] = state


func _enter_initial_state() -> void:
	if _states.is_empty():
		return
	if not _states.has(initial_state):
		var first_key: Variant = _states.keys()[0]
		initial_state = first_key as StringName
	change_state(initial_state, {}, true)
