class_name LkWorldClock
extends RefCounted

const MAX_EPOCH_S: float = 1.0e12
var _epoch_s: float = 0.0
var _compensation: float = 0.0


func now_s() -> float:
	return _epoch_s


# Startup/restore API; do not rewind an already-bound live world.
func restore(epoch_s: float) -> bool:
	if not is_finite(epoch_s) or epoch_s < 0.0 or epoch_s > MAX_EPOCH_S:
		return false
	_epoch_s = epoch_s
	_compensation = 0.0
	return true


# Called ONCE by the world owner, never once per body. No OS wall clock.
func advance(delta_s: float) -> bool:
	if not is_finite(delta_s) or delta_s < 0.0:
		return false
	if delta_s == 0.0:
		return true
	var corrected: float = delta_s - _compensation
	var next: float = _epoch_s + corrected
	if not is_finite(next) or next > MAX_EPOCH_S:
		return false
	_compensation = (next - _epoch_s) - corrected
	_epoch_s = next
	return true
