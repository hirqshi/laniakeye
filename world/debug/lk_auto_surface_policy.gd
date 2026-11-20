class_name LkAutoSurfacePolicy
extends RefCounted

static func should_start(height: float, closing_speed: float, max_height: float, horizon_s: float = 30.0, hover_height: float = 1500.0) -> bool:
	for value: float in [height, closing_speed, max_height, horizon_s, hover_height]:
		if not is_finite(value):
			return false
	if max_height <= 0.0 or horizon_s <= 0.0 or hover_height < 0.0 or height < 0.5 or height > max_height + 2.0 or closing_speed < -1.0:
		return false
	return height <= hover_height or (closing_speed > 0.1 and height / closing_speed <= horizon_s)

static func surface_target(fixed: LkPosition64, radius: float) -> Dictionary:
	var length: float = fixed.length()
	if not is_finite(length) or length <= 0.0 or not is_finite(radius) or radius <= 0.0:
		return {"ok": false}
	var scale: float = (radius + 1.0) / length
	return {"ok": true, "point": LkPosition64.new(fixed.x * scale, fixed.y * scale, fixed.z * scale)}

static func in_target(point: LkPosition64, target: LkPosition64, radius: float) -> bool:
	return radius >= 0.0 and point.minus(target).length() <= radius
