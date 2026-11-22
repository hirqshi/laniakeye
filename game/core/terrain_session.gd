class_name LkTerrainSession
extends RefCounted
## Explicit terrain lifecycle. Terrain readiness is independent of player mode
## and of physical support (active body, ready terrain and floor contact are separate facts).
## Replaces combinations of _auto_busy, _landing_preparing, _movement_paused, _stream_hold, _pending.

signal changed(from_state: int, to_state: int, reason: String)

enum State { IDLE, PREPARING, STAGED, ACTIVE, REANCHORING, ROLLBACK }

const ALLOWED: Dictionary = {
	State.IDLE: [State.PREPARING, State.ACTIVE],
	State.PREPARING: [State.STAGED, State.IDLE, State.ACTIVE],
	State.STAGED: [State.ACTIVE, State.IDLE, State.ROLLBACK],
	State.ACTIVE: [State.PREPARING, State.REANCHORING, State.IDLE],
	State.REANCHORING: [State.ACTIVE, State.ROLLBACK],
	State.ROLLBACK: [State.ACTIVE, State.IDLE],
}

var current: int = State.IDLE
var body_id: StringName = StringName()
var revision: int = 0
var reason: String = ""
var last_error: String = ""


func bind_body(new_body_id: StringName, new_revision: int) -> void:
	body_id = new_body_id
	revision = new_revision


func can_transition(to_state: int) -> bool:
	if to_state == current:
		return false
	var targets: Array = ALLOWED.get(current, [])
	return targets.has(to_state)


func request(to_state: int, why: String = "") -> bool:
	if not can_transition(to_state):
		last_error = "illegal transition %s -> %s" % [state_name(current), state_name(to_state)]
		return false
	var from_state: int = current
	current = to_state
	reason = why
	last_error = ""
	changed.emit(from_state, to_state, why)
	return true


func is_edit_allowed() -> bool:
	return current == State.ACTIVE


func is_transitioning() -> bool:
	return current == State.PREPARING or current == State.STAGED or current == State.REANCHORING or current == State.ROLLBACK


static func state_name(state: int) -> String:
	return str(State.find_key(state))
