extends SceneTree

const Carry = preload("res://world/debug/lk_debug_flight_carry.gd")
const Frame = preload("res://core/refactor_v1/rotating_frame.gd")
const FlightScene = preload("res://scenes/world/test_catalog_debug_flight.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("FlightCarry: FAIL " + label)

func _initialize() -> void:
	var earth: Dictionary = Carry.band(6371000.0, 9.81)
	_check(earth["ok"] and is_equal_approx(earth["inner_m"], 200000.0) and is_equal_approx(earth["outer_m"], 300000.0), "Earth reference band")
	_check(Carry.weight(0.0, earth) == 1.0 and Carry.weight(199999.0, earth) == 1.0, "full below band")
	_check(is_equal_approx(Carry.weight(250000.0, earth), 0.5), "half midpoint")
	_check(Carry.weight(300000.0, earth) == 0.0 and Carry.weight(1.0e9, earth) == 0.0, "none above band")
	var previous: float = 1.0
	for i: int in range(1001):
		var value: float = Carry.weight(200000.0 + float(i) * 100.0, earth)
		_check(is_finite(value) and value >= 0.0 and value <= previous, "bounded monotonic blend")
		previous = value
	_check(absf(Carry.weight(200000.001, earth) - 1.0) < 1.0e-9, "inner boundary continuity")
	_check(absf(Carry.weight(299999.999, earth)) < 1.0e-9, "outer boundary continuity")
	var small: Dictionary = Carry.band(1737400.0, 1.62)
	var giant: Dictionary = Carry.band(69911000.0, 24.79)
	_check(small["middle_m"] < earth["middle_m"] and giant["middle_m"] > earth["middle_m"], "radius/gravity scaling")
	var tiny: Dictionary = Carry.band(10.0, 0.0)
	_check(tiny["ok"] and tiny["middle_m"] <= 2.5, "tiny-body cap")
	var fixed: Dictionary = Carry.band(1737400.0, 1.62, 250000.0, false)
	_check(fixed["middle_m"] == 250000.0, "adaptive disabled")
	var overridden: Dictionary = Carry.band(1737400.0, 1.62, 250000.0, true, 10000.0)
	_check(overridden["middle_m"] == 10000.0, "explicit override")
	_check(not Carry.band(-1.0, 9.81)["ok"] and not Carry.band(1.0, INF)["ok"], "invalid inputs")
	_check(Carry.weight(INF, earth) == 0.0, "nonfinite height")
	var frame = Frame.new(&"fixture", LkPosition64.new(), Vector3.UP, TAU / 1800.0)
	var point: LkPosition64 = LkPosition64.new(1.0e9, 0.0, 0.0)
	var angle: float = frame.angular_speed_rad_s * 0.5
	var moved: LkPosition64 = point.plus(frame.carry_displacement64(point, angle))
	_check(absf(moved.length() - point.length()) < 1.0e-5, "weighted rotation preserves radius")
	_check(moved.minus(frame.rotate(point, angle)).length() < 1.0e-5, "weighted displacement matches rotation")
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_debug_flight.gd")
	_check(source.contains("FLIGHT_ADAPTIVE_CARRY_V1") and source.contains("carry_displacement64") and source.contains("Surface carry"), "installed flight integration")
	if _failures == 0:
		print("FlightCarry: PASS Earth band, adaptive scale, smooth weight, limits, override, radius preservation, scene parse")
	print("FlightCarry: visual transition and landing still need integration test")
	quit(0 if _failures == 0 else 1)
