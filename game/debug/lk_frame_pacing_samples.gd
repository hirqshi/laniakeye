class_name LkFramePacingSamples
extends RefCounted

var capacity: int = 1200
var _states: Dictionary = {}

func _init(limit: int = 1200) -> void:
	capacity = clampi(limit, 16, 10000)

func add(state: String, milliseconds: float) -> void:
	if state.is_empty() or not is_finite(milliseconds) or milliseconds <= 0.0:
		return
	if not _states.has(state):
		_states[state] = {"values": [], "cursor": 0, "total": 0}
	var bucket: Dictionary = _states[state]
	var values: Array = bucket["values"]
	if values.size() < capacity:
		values.append(milliseconds)
	else:
		values[int(bucket["cursor"])] = milliseconds
		bucket["cursor"] = (int(bucket["cursor"]) + 1) % capacity
	bucket["values"] = values
	bucket["total"] = int(bucket["total"]) + 1

func states() -> Array:
	return _states.keys()

func summary(state: String) -> Dictionary:
	if not _states.has(state):
		return {}
	var values: Array = _states[state]["values"].duplicate()
	if values.is_empty():
		return {}
	values.sort()
	var total: float = 0.0
	for value: float in values:
		total += value
	var n: int = values.size()
	return {"state": state, "n": n, "seen": _states[state]["total"], "mean_ms": total / float(n),
		"p95_ms": values[clampi(int(ceil(float(n) * 0.95)) - 1, 0, n - 1)],
		"p99_ms": values[clampi(int(ceil(float(n) * 0.99)) - 1, 0, n - 1)], "max_ms": values[n - 1]}

static func allow_growth(frame_ms: float, baseline_ms: float, target_ms: float, main_queue: int) -> bool:
	if not is_finite(frame_ms) or frame_ms <= 0.0:
		return false
	var limit: float = maxf(target_ms, baseline_ms) * 1.15
	return frame_ms <= limit and (main_queue < 0 or main_queue <= 64)
