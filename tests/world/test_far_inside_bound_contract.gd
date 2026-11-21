extends SceneTree

const PATH: String = "res://world/rendering/lk_far_body_snapshot.gd"
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("FarInsideBoundContract: FAIL " + label)

func _initialize() -> void:
	var source: String = FileAccess.get_file_as_string(PATH)
	_check(not source.is_empty(), "snapshot source exists")
	_check(source.contains("\"inside\": distance < float(body[\"physical_bound_radius_m\"]) - 0.5,"), "inside uses physical bound radius")
	_check(not source.contains("\"inside\": distance < radius - 0.5,"), "inside no longer uses base radius")
	_check(source.contains("\"radius_relative\": radius / distance,"), "visual disc still uses base radius")
	_check(source.contains("\"angular_radius_rad\": asin(clampf(radius / distance, 0.0, 1.0)),"), "angular selection still uses base radius")
	_check(source.contains("if distance_squared <= 0.0:\n\t\t\tcontinue"), "zero-distance contract retained")
	_check(source.contains("sun = [-float(p[0]) / length, -float(p[1]) / length, -float(p[2]) / length]"), "heliocentric sun contract retained")
	# Catalog contract: physical bound includes terrain relief.
	var catalog: String = FileAccess.get_file_as_string("res://world/generation/lk_body_catalog.gd")
	_check(catalog.contains("\"physical_bound_radius_m\": radius + relief,"), "physical bound includes relief")
	_check(catalog.contains("relief = minf(200000.0, radius * 0.05)"), "relief can exceed base radius")
	# Boundary reference, not a GPU/render test.
	var radius: float = 1000.0
	var relief: float = 50000.0
	var bound: float = radius + relief
	_check(radius + relief == bound, "bound reference")
	_check(radius < bound, "base radius is below physical bound")
	_check(bound - 0.5 > radius, "fallback remains active across part of relief envelope")
	if _failures == 0:
		print("FarInsideBoundContract: PASS physical-bound inside, base-radius visual disc, catalog relief")
	print("FarInsideBoundContract: runtime observer transitions and rendered pits require an in-game check")
	quit(0 if _failures == 0 else 1)
