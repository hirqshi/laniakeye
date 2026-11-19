extends SceneTree

const FlightMath = preload("res://world/debug/lk_debug_flight_math.gd")
const FlightScene = preload("res://scenes/world/test_catalog_debug_flight.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("DebugFlight: FAIL " + label)

func _initialize() -> void:
	var previous: float = 0.0
	for height: float in [0.0, 1.0, 10.0, 100.0, 1000.0, 1.0e6, 1.0e9, 1.0e12]:
		var speed: float = FlightMath.speed_at_height(height)
		_check(is_finite(speed) and speed >= previous and speed <= 1.0e11, "finite monotonic speed")
		previous = speed
	_check(is_equal_approx(FlightMath.speed_at_height(100.0, 2.0), FlightMath.speed_at_height(100.0) * 2.0), "manual multiplier")
	_check(FlightMath.speed_at_height(INF) == 0.0, "invalid height refused")
	var sphere: Array = [{"center": [10.0, 0.0, 0.0], "radius": 2.0}]
	_check(is_equal_approx(FlightMath.safe_step(Vector3.RIGHT, 1000.0, sphere), 7.5), "no tunnelling across full sphere")
	_check(FlightMath.safe_step(Vector3.LEFT, 1000.0, sphere) == 1000.0, "moving away")
	_check(FlightMath.safe_step(Vector3.UP, 1000.0, sphere) == 1000.0, "miss")
	_check(FlightMath.safe_step(Vector3.RIGHT, 1.0, sphere) == 1.0, "short unobstructed step")
	_check(FlightMath.safe_step(Vector3.ZERO, 1.0, sphere) == 0.0, "zero input")
	var inside: Array = [{"center": [1.0, 0.0, 0.0], "radius": 2.0}]
	_check(FlightMath.safe_step(Vector3.RIGHT, 100.0, inside) == 0.0, "inside inward blocked")
	_check(FlightMath.safe_step(Vector3.LEFT, 100.0, inside) == 100.0, "inside outward recovery")
	var distant: Array = [{"center": [1.0e12, 0.0, 0.0], "radius": 1.0e6}]
	var allowed: float = FlightMath.safe_step(Vector3.RIGHT, 2.0e12, distant)
	_check(allowed > 0.0 and allowed < 1.0e12 - 1.0e6, "astronomical scalar centres")
	var multiple: Array = [{"center": [100.0, 0.0, 0.0], "radius": 5.0}, sphere[0]]
	_check(is_equal_approx(FlightMath.safe_step(Vector3.RIGHT, 1000.0, multiple), 7.5), "nearest collision wins")
	if _failures == 0:
		print("DebugFlight: PASS speed curve, multiplier, finite guards, full-segment sphere tests, scene parse")
	print("DebugFlight: integration NOT tested: flight/landing, terrain guards, clock, navigation, origin and rendering")
	quit(0 if _failures == 0 else 1)
