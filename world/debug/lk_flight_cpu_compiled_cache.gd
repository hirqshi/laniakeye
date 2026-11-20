extends "res://world/debug/lk_flight_cpu_state_cache.gd"

const CompiledLayout = preload("res://world/debug/lk_compiled_orbit_layout.gd")
var compiled_enabled: bool = true
var compiled = CompiledLayout.new()

func configure(layout: Dictionary) -> bool:
	_layout = {}
	invalidate()
	compiled = CompiledLayout.new()
	if not super.configure(layout):
		return false
	if not compiled.configure(_layout):
		_layout = {}
		invalidate()
		return false
	return true

func set_compiled_enabled(enabled: bool) -> void:
	compiled_enabled = enabled
	invalidate()

func get_states(epoch: float) -> Dictionary:
	if not compiled_enabled:
		return super.get_states(epoch)
	if _layout.is_empty() or not is_finite(epoch):
		return {}
	if epoch == _epoch and not _value.is_empty():
		hits += 1
		return _value
	var started: int = Time.get_ticks_usec()
	var states: Dictionary = compiled.evaluate(epoch)
	evaluate_us += Time.get_ticks_usec() - started
	builds += 1
	if states.is_empty():
		return {}
	_epoch = epoch
	_value = states
	return _value
