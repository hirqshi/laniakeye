class_name LkWarmActivationPolicy
extends RefCounted

const ACTIVATE_GAP_M: float = 48.0
const REUSE_DISTANCE_M: float = 96.0

static func action(height: float, gap: float, reusable: bool, activation_height: float,
	blocked_seconds: float, grace_seconds: float = 0.25) -> String:
	for value: float in [height, gap, activation_height, blocked_seconds, grace_seconds]:
		if not is_finite(value):
			return "INVALID"
	if gap < 0.0 or activation_height <= 0.0:
		return "INVALID"
	if height > activation_height:
		return "WAIT_HEIGHT"
	if gap <= ACTIVATE_GAP_M:
		return "ALIGN_OR_VALIDATE"
	if blocked_seconds < maxf(0.0, grace_seconds):
		return "SETTLE_TARGET"
	return "RECENTER" if reusable else "RETARGET"

static func reusable(actual: LkPosition64, anchor: LkPosition64) -> bool:
	var distance: float = actual.minus(anchor).length()
	return is_finite(distance) and distance <= REUSE_DISTANCE_M
