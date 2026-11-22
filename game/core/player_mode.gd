class_name LkPlayerMode
extends RefCounted
## Explicit player control state machine.
## Replaces scattered booleans (_flight_active, _contact6_active, _control5_assisted, ...).
## Only transitions listed in ALLOWED are legal. Tighten the table as systems migrate.

signal changed(from_mode: int, to_mode: int, reason: String)

enum Mode { NONE, DEBUG_FLIGHT, EVA, CONTACT_ACQUIRE, WALK, TRANSFER }

const ALLOWED: Dictionary = {
	Mode.NONE: [Mode.DEBUG_FLIGHT, Mode.EVA, Mode.WALK],
	Mode.DEBUG_FLIGHT: [Mode.NONE, Mode.EVA, Mode.CONTACT_ACQUIRE, Mode.TRANSFER],
	Mode.EVA: [Mode.NONE, Mode.DEBUG_FLIGHT, Mode.CONTACT_ACQUIRE, Mode.WALK, Mode.TRANSFER],
	Mode.CONTACT_ACQUIRE: [Mode.WALK, Mode.DEBUG_FLIGHT],
	Mode.WALK: [Mode.NONE, Mode.DEBUG_FLIGHT, Mode.EVA],
	Mode.TRANSFER: [Mode.DEBUG_FLIGHT, Mode.EVA, Mode.WALK],
}

var current: int = Mode.NONE
var previous: int = Mode.NONE
var reason: String = ""
var last_error: String = ""


func can_transition(to_mode: int) -> bool:
	if to_mode == current:
		return false
	var targets: Array = ALLOWED.get(current, [])
	return targets.has(to_mode)


func request(to_mode: int, why: String = "") -> bool:
	if not can_transition(to_mode):
		last_error = "illegal transition %s -> %s" % [mode_name(current), mode_name(to_mode)]
		return false
	var from_mode: int = current
	previous = from_mode
	current = to_mode
	reason = why
	last_error = ""
	changed.emit(from_mode, to_mode, why)
	return true


func is_airborne_control() -> bool:
	return current == Mode.DEBUG_FLIGHT or current == Mode.EVA


func is_physical() -> bool:
	return current == Mode.EVA or current == Mode.CONTACT_ACQUIRE or current == Mode.WALK


static func mode_name(mode: int) -> String:
	return str(Mode.find_key(mode))
