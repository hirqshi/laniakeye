extends RefCounted

# A debug surface-control policy, NOT the physical gravity-service up threshold.
static func classify(magnitude: float, assist_threshold: float) -> String:
	if not is_finite(magnitude) or magnitude < 0.0 or not is_finite(assist_threshold) or assist_threshold <= 0.0:
		return "INVALID"
	return "EVA_ASSIST" if magnitude < assist_threshold else "NORMAL"

static func speed(original: float, assisted: bool, maximum: float) -> float:
	if not assisted:
		return original
	if not is_finite(original) or not is_finite(maximum) or maximum <= 0.0:
		return 0.0
	return clampf(original, 0.0, maximum)
