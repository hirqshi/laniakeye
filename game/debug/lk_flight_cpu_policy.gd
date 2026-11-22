class_name LkFlightCpuPolicy
extends RefCounted

static func navigation_due(age_s: float, rate_hz: float, force: bool) -> bool:
	if force:
		return true
	if not is_finite(age_s) or not is_finite(rate_hz) or rate_hz <= 0.0:
		return false
	return age_s >= 1.0 / clampf(rate_hz, 5.0, 120.0)
