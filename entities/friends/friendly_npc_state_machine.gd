extends Node
class_name FriendlyNPCStateMachine

signal state_changed(previous_state: State, current_state: State)

enum State {
	IDLE,
	WANDER,
	TALK,
	FLEE,
}

var current_state: State = State.IDLE
var previous_state: State = State.IDLE


func change_state(next_state: State, force: bool = false) -> bool:
	if not force and next_state == current_state:
		return false
	previous_state = current_state
	current_state = next_state
	state_changed.emit(previous_state, current_state)
	return true


func get_state_name() -> StringName:
	return State.keys()[current_state].to_lower()
