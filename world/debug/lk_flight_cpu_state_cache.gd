class_name LkFlightCpuStateCache
extends RefCounted

const Layout = preload("res://world/generation/lk_safe_orbit_layout.gd")
var builds: int = 0
var hits: int = 0
var evaluate_us: int = 0
var _layout: Dictionary = {}
var _signature: PackedByteArray
var _epoch: float = NAN
var _value: Dictionary = {}

static func signature(layout: Dictionary) -> PackedByteArray:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(layout))
	return context.finish()

func configure(layout: Dictionary) -> bool:
	if layout.get("layout_version", -1) != 1 or String(layout.get("system_id", "")).is_empty():
		return false
	_layout = layout.duplicate(true)
	_signature = signature(layout)
	invalidate()
	builds = 0
	hits = 0
	evaluate_us = 0
	return true

func matches(layout: Dictionary) -> bool:
	return not _layout.is_empty() and signature(layout) == _signature

func invalidate() -> void:
	_epoch = NAN
	_value = {}

# BORROWED READ-ONLY contract. No deep-copy on hits. All registered consumers
# only read state values; callers must not mutate returned dictionaries/arrays.
func get_states(epoch: float) -> Dictionary:
	if _layout.is_empty() or not is_finite(epoch):
		return {}
	if epoch == _epoch and not _value.is_empty():
		hits += 1
		return _value
	var started: int = Time.get_ticks_usec()
	var states: Dictionary = Layout.evaluate(_layout, epoch)
	evaluate_us += Time.get_ticks_usec() - started
	builds += 1
	if states.is_empty():
		return {}
	_epoch = epoch
	_value = states
	return _value
