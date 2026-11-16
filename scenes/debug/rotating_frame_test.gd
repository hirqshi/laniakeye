extends Node3D

const EARTH_RADIUS_M: float = 6371000.0
const EARTH_OMEGA: float = 7.2921e-5
const TICK_S: float = 1.0 / 60.0
const TICKS: int = 108000

var _label: Label
var _failures: int = 0
var _lines: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_test_carry_matches_exact_rotation()
	_test_equatorial_step_length()
	_test_velocity_roundtrip()
	_test_zero_rate_is_inert()
	_test_basis_matches_rotate()
	var canvas: CanvasLayer = CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.text = "RotatingFrame math gate: %s\n%s" % ["ALL PASS" if _failures == 0 else "FAIL (%d)" % _failures, "\n".join(_lines)]
	canvas.add_child(_label)
	add_child(canvas)
	print("RotatingFrameTest: ", "ALL PASS" if _failures == 0 else "FAIL %d" % _failures)


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_failures += 1
		push_error("RotatingFrameTest: %s FAILED %s" % [name, detail])
	_lines.append("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])


func _test_carry_matches_exact_rotation() -> void:
	var frame: LkRotatingFrame = LkRotatingFrame.new(&"earth", LkPosition64.new(149597870700.0, 0.0, 0.0), Vector3(sin(0.4), cos(0.4), 0.0), EARTH_OMEGA)
	var rel0: LkPosition64 = LkPosition64.new(0.0, EARTH_RADIUS_M * 0.8, EARTH_RADIUS_M * 0.6)
	var origin_rel: LkPosition64 = rel0.copy()
	var local: Vector3 = Vector3.ZERO
	var total_angle: float = 0.0
	for i: int in range(TICKS):
		var step: float = frame.advance(TICK_S)
		total_angle += step
		var rel: LkPosition64 = origin_rel.plus_local(local)
		local += frame.carry_displacement(rel, step)
		if local.length() > 64.0:
			origin_rel = origin_rel.plus_local(local)
			local = Vector3.ZERO
	var final_rel: LkPosition64 = origin_rel.plus_local(local)
	var exact: LkPosition64 = frame.rotate(rel0, total_angle)
	var error_m: float = final_rel.minus(exact).length()
	var radius_drift_m: float = absf(final_rel.length() - rel0.length())
	_check("carry vs exact (30 min, Earth)", error_m < 0.005 and radius_drift_m < 0.005, "err=%.6f m radius_drift=%.6f m" % [error_m, radius_drift_m])


func _test_equatorial_step_length() -> void:
	var frame: LkRotatingFrame = LkRotatingFrame.new(&"eq", LkPosition64.new(0.0, 0.0, 0.0), Vector3.UP, EARTH_OMEGA)
	var rel: LkPosition64 = LkPosition64.new(EARTH_RADIUS_M, 0.0, 0.0)
	var step: float = frame.advance(TICK_S)
	var expected: float = EARTH_OMEGA * EARTH_RADIUS_M * TICK_S
	var actual: float = frame.carry_displacement(rel, step).length()
	_check("equatorial step length", absf(actual - expected) / expected < 0.00001, "actual=%.9f expected=%.9f" % [actual, expected])


func _test_velocity_roundtrip() -> void:
	var frame: LkRotatingFrame = LkRotatingFrame.new(&"v", LkPosition64.new(0.0, 0.0, 0.0), Vector3.UP, EARTH_OMEGA)
	var rel: LkPosition64 = LkPosition64.new(EARTH_RADIUS_M, 100.0, 0.0)
	var velocity: Vector3 = Vector3(1.5, -2.0, 0.5)
	var back: Vector3 = frame.to_relative_velocity(frame.to_inertial_velocity(velocity, rel), rel)
	_check("velocity roundtrip", (back - velocity).length() < 0.001, "diff=%.9f m/s surface=%.3f m/s" % [(back - velocity).length(), frame.surface_velocity(rel).length()])


func _test_zero_rate_is_inert() -> void:
	var frame: LkRotatingFrame = LkRotatingFrame.new(&"z", LkPosition64.new(0.0, 0.0, 0.0), Vector3.UP, 0.0)
	var rel: LkPosition64 = LkPosition64.new(EARTH_RADIUS_M, 0.0, 0.0)
	var step: float = frame.advance(TICK_S)
	var displacement: Vector3 = frame.carry_displacement(rel, step)
	_check("zero rate inert", displacement.length() == 0.0 and frame.surface_velocity(rel).length() == 0.0, "disp=%s" % displacement)


func _test_basis_matches_rotate() -> void:
	var frame: LkRotatingFrame = LkRotatingFrame.new(&"b", LkPosition64.new(0.0, 0.0, 0.0), Vector3(1.0, 2.0, 3.0), 0.5)
	var rel: LkPosition64 = LkPosition64.new(600.0, -300.0, 800.0)
	var angle: float = 0.7
	var by_rotate: LkPosition64 = frame.rotate(rel, angle)
	var by_basis: Vector3 = Basis(frame.get_axis(), angle) * Vector3(rel.x, rel.y, rel.z)
	var diff: float = Vector3(by_rotate.x, by_rotate.y, by_rotate.z).distance_to(by_basis)
	_check("basis matches rotate", diff < 0.001, "diff=%.6f m" % diff)


func _test_round_trip_at_planet_scale() -> void:
	var frame: LkRotatingFrame = LkRotatingFrame.new(&"rt", LkPosition64.new(0.0, 0.0, 0.0), Vector3(0.3, 0.9, 0.1), EARTH_OMEGA)
	var rel: LkPosition64 = LkPosition64.new(4505206.0, 4505206.0, 0.0)
	var worst_m: float = 0.0
	for degrees: float in [1.0, 10.0, 45.0, 90.0, 179.0]:
		var angle: float = deg_to_rad(degrees)
		var back: LkPosition64 = frame.rotate(frame.rotate(rel, angle), -angle)
		worst_m = maxf(worst_m, back.minus(rel).length())
	_check("rotate round trip at planet scale", worst_m < 0.000001, "worst=%.9f m" % worst_m)
