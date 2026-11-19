class_name LkRotationPeriods
extends RefCounted

const Samples = preload("res://world/generation/lk_world_samples.gd")
# Version 1 was the implicit 6..120 hour recipe in orbit layout v1.
const VERSION: int = 2
const MIN_PERIOD_S: float = 1200.0
const CORE_MIN_S: float = 1800.0
const CORE_MAX_S: float = 10800.0
const MAX_PERIOD_S: float = 144000.0


# Pure mapping; callers provide samples in [0, 1]. Endpoints permit fixtures.
static func from_samples(band: float, fraction: float) -> float:
	if not is_finite(band) or not is_finite(fraction) or band < 0.0 or band > 1.0 or fraction < 0.0 or fraction > 1.0:
		push_error("RotationPeriods: samples outside [0,1]")
		return NAN
	var first: float = CORE_MIN_S
	var last: float = CORE_MAX_S
	if band < 0.05:
		first = MIN_PERIOD_S
		last = CORE_MIN_S
	elif band >= 0.90:
		first = CORE_MAX_S
		last = MAX_PERIOD_S
	return clampf(exp(log(first) + fraction * (log(last) - log(first))), first, last)


static func period_s(body_id: String) -> float:
	return from_samples(
		Samples.unit(body_id, "rotation/band", VERSION),
		Samples.unit(body_id, "rotation/fraction", VERSION)
	)
