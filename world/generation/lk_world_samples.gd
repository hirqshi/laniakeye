class_name LkWorldSamples
extends RefCounted

const Identity = preload("res://world/generation/lk_world_identity.gd")
const UNIT_DENOMINATOR: float = 9007199254740992.0


# Protocol v1: high 53 bits of a nonnegative 63-bit derived seed.
# Named samples have no shared mutable PRNG state.
static func unit(object_id: String, domain: String, version: int) -> float:
	var bits: int = Identity.seed63(object_id, domain, version)
	if bits < 0:
		return -1.0
	return float(bits >> 10) / UNIT_DENOMINATOR


static func range_int(
	object_id: String,
	domain: String,
	version: int,
	minimum: int,
	maximum: int
) -> int:
	if maximum < minimum:
		push_error("LkWorldSamples: invalid range")
		return minimum
	var sample: float = unit(object_id, domain, version)
	if sample < 0.0:
		return minimum
	return minimum + int(floor(sample * float(maximum - minimum + 1)))
