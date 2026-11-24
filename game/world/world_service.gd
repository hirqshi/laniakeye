class_name LkWorldService
extends RefCounted
## Resolves catalog bodies and owns the active body: its context and its clocked frame.
## Reads the shared clock from LkClockService and never advances it.

signal activated(body_id: StringName)
signal deactivated(body_id: StringName)
signal failed(reason: String)

const Context = preload("res://game/world/runtime/lk_body_context.gd")
const BodyFrame = preload("res://game/world/runtime/lk_clocked_body_frame.gd")
const Lighting = preload("res://game/world/runtime/lk_stellar_lighting.gd")
const ADDRESS_KEYS: Array = ["galaxy", "x", "y", "z", "system_slot", "planet_slot"]

var definition
var last_error: String = ""
var active_context: Dictionary = {}
var active_frame = null
var _clock_service


func _init(new_definition, clock_service) -> void:
	definition = new_definition
	_clock_service = clock_service


static func make_address(galaxy: int, x: int, y: int, z: int, system_slot: int, planet_slot: int) -> Dictionary:
	return {"galaxy": galaxy, "x": x, "y": y, "z": z, "system_slot": system_slot, "planet_slot": planet_slot}


func has_active() -> bool:
	return active_frame != null


func active_body_id() -> StringName:
	if active_context.is_empty():
		return StringName()
	return StringName(active_context["body"]["id"])


## Returns the body context for an address, or an empty Dictionary when it does not resolve.
func resolve(address: Dictionary) -> Dictionary:
	for key in ADDRESS_KEYS:
		if not address.has(key):
			_fail("body address is missing '%s'" % key)
			return {}
	return Context.resolve(definition, int(address["galaxy"]), int(address["x"]), int(address["y"]), int(address["z"]), int(address["system_slot"]), int(address["planet_slot"]))


## Makes the body at `address` active. The previous body stays active if this fails.
func activate(address: Dictionary) -> bool:
	if _clock_service == null or not _clock_service.is_open():
		return _fail("world clock must be open before a body is activated")
	var context: Dictionary = resolve(address)
	if context.is_empty():
		return _fail("body address does not resolve")
	var previous: StringName = active_body_id()
	var frame = BodyFrame.new(StringName(context["body"]["id"]), context["spin"], _clock_service.get_clock())
	active_context = context
	active_frame = frame
	last_error = ""
	if previous != StringName():
		deactivated.emit(previous)
	activated.emit(active_body_id())
	return true


func deactivate() -> void:
	if active_frame == null:
		return
	var previous: StringName = active_body_id()
	active_context = {}
	active_frame = null
	deactivated.emit(previous)


## Syncs the active frame to the shared clock. Call after the clock advanced for this tick.
func tick(delta_s: float) -> float:
	if active_frame == null:
		return 0.0
	return active_frame.advance(delta_s)


## Sun direction and horizon data for an observer position in the active body's axes.
func lighting_at(q_body: Array) -> Dictionary:
	if active_frame == null or _clock_service == null or not _clock_service.is_open():
		return {}
	return Lighting.evaluate(active_context["orbit"], active_context["spin"], _clock_service.now_s(), q_body)


func _fail(reason: String) -> bool:
	last_error = reason
	failed.emit(reason)
	return false
