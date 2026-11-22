class_name LkClockService
extends RefCounted
## Single owner of the universe clock.
## Loads the saved epoch, advances it exactly once per physics tick, autosaves and
## saves on demand. Body frames only READ the clock; they never advance it.

signal failed(reason: String)

const ClockStore = preload("res://game/world/runtime/lk_world_clock_store.gd")
const DEFAULT_AUTOSAVE_INTERVAL_S: float = 30.0

var autosave_interval_s: float = DEFAULT_AUTOSAVE_INTERVAL_S
var universe_id: String = ""
var loaded_existing: bool = false
var last_error: String = ""
var _clock = null
var _since_save_s: float = 0.0


func is_open() -> bool:
	return _clock != null


## The shared LkWorldClock for read-only use by body frames. Null while closed.
func get_clock():
	return _clock


func now_s() -> float:
	if _clock == null:
		return 0.0
	return _clock.now_s()


func open(new_universe_id: String) -> bool:
	if _clock != null:
		return _fail("world clock already open; close it first")
	var loaded: Dictionary = ClockStore.load_clock(new_universe_id)
	if not loaded["ok"]:
		return _fail("world clock: " + str(loaded["error"]))
	universe_id = new_universe_id
	_clock = loaded["clock"]
	loaded_existing = loaded["found"]
	_since_save_s = 0.0
	last_error = ""
	return true


## Call exactly once per physics tick from the world owner.
func advance(delta_s: float) -> bool:
	if _clock == null:
		return _fail("world clock is not open")
	if not _clock.advance(delta_s):
		return _fail("world clock rejected delta")
	_since_save_s += delta_s
	if _since_save_s >= autosave_interval_s:
		return save()
	return true


func save() -> bool:
	if _clock == null:
		return _fail("world clock is not open")
	if not ClockStore.save_clock(universe_id, _clock):
		return _fail("world clock save failed")
	_since_save_s = 0.0
	return true


## Saves and releases the clock. If saving fails the clock stays open so the caller can retry.
func close() -> bool:
	if _clock == null:
		return true
	if not save():
		return false
	_clock = null
	universe_id = ""
	loaded_existing = false
	return true


func _fail(reason: String) -> bool:
	last_error = reason
	failed.emit(reason)
	return false
