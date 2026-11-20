extends SceneTree

const ReferenceMath = preload("res://world/debug/lk_debug_flight_math.gd")
const PackedMath = preload("res://world/debug/lk_debug_flight_math_packed.gd")
const ReferencePool = preload("res://world/debug/lk_flight_sphere_pool.gd")
const PackedPool = preload("res://world/debug/lk_flight_sphere_pool_packed.gd")
const SceneScript = preload("res://scenes/world/test_catalog_flight_cpu_v6.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("FlightCPU6: FAIL " + label)

func _initialize() -> void:
	var star: Dictionary = {"id": "star", "radius_m": 1000000.0}
	var planet: Dictionary = {"id": "planet", "radius_m": 1000.0}
	var moon: Dictionary = {"id": "moon", "radius_m": 100.0}
	var layout: Dictionary = {"layout_version": 1, "system_id": "cpu6-fixture", "star": star, "planets": [{"body": planet, "moons": [{"body": moon}]}]}
	var states: Dictionary = {"system_id": "cpu6-fixture", "time_s": 12.25, "bodies": [
		{"id": "star", "position_m": [0.0, 0.0, 0.0]},
		{"id": "planet", "position_m": [1.0e12 + 0.125, -3.75, 2.5]},
		{"id": "moon", "position_m": [1.0e12 + 10000000.125, -3.75, 2.5]}]}
	var reference_pool = ReferencePool.new()
	var packed_pool = PackedPool.new()
	_check(reference_pool.configure(layout, "planet"), "reference pool bind")
	_check(packed_pool.configure(layout, "planet"), "packed pool bind")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 430
	var guard_checks: int = 0
	for i: int in range(32):
		var observer: LkPosition64 = LkPosition64.new(1002.0 + float(i) * 0.125, 3.5, -2.0)
		var ready: bool = i % 2 == 0
		var legacy_rows: Array = reference_pool.build(states, observer, 12.25, ready)
		_check(packed_pool.build_packed(states, observer, 12.25, ready), "packed build")
		_check(packed_pool.count == 3 and packed_pool.centers.size() == 9 and packed_pool.radii.size() == 3, "packed buffer sizes")
		for index: int in range(3):
			var row: Dictionary = legacy_rows[index]
			_check(packed_pool.centers[3 * index] == float(row["center"][0]) and packed_pool.centers[3 * index + 1] == float(row["center"][1]) and packed_pool.centers[3 * index + 2] == float(row["center"][2]), "centre parity")
			_check(packed_pool.radii[index] == float(row["radius"]), "radius parity")
		_check(packed_pool.nearest_height == reference_pool.nearest_height and packed_pool.nearest_label == reference_pool.nearest_label, "nearest parity")
		for j: int in range(12):
			var direction: Vector3 = Vector3(-1.0, 0.0, 0.0) if j == 0 else Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
			var request: float = 1.0e12 if j % 2 == 0 else 100.0
			var expected: float = ReferenceMath.safe_step(direction, request, legacy_rows)
			var actual: float = PackedMath.safe_step_packed(direction, request, packed_pool.centers, packed_pool.radii)
			_check(actual == expected, "safe-step exact parity")
			guard_checks += 1
	# Inside-sphere outward recovery and direct hit remain exact.
	var inside: LkPosition64 = LkPosition64.new(500.0, 0.0, 0.0)
	packed_pool.build_packed(states, inside, 12.25, true)
	var inside_rows: Array = reference_pool.build(states, inside, 12.25, true)
	var direction: Vector3 = Vector3(1.0, 0.0, 0.0)
	_check(
		PackedMath.safe_step_packed(
			direction, 100.0, packed_pool.centers, packed_pool.radii
		) == ReferenceMath.safe_step(direction, 100.0, inside_rows),
		"inside outward recovery"
	)
	_check(packed_pool.build_packed(states, inside, 12.250001, true) == false and not packed_pool.valid, "wrong epoch rejected")
	var reordered: Dictionary = states.duplicate(true)
	reordered["bodies"].reverse()
	_check(packed_pool.build_packed(reordered, inside, 12.25, true) == false, "ID order cannot attach wrong radius")
	var invalid: Dictionary = states.duplicate(true)
	invalid["bodies"][2]["position_m"][0] = INF
	_check(packed_pool.build_packed(invalid, inside, 12.25, true) == false, "invalid position refused")
	_check(not PackedPool.new().configure(layout, "missing"), "missing active body refused")
	packed_pool.build_packed(states, inside, 12.25, true)
	_check(packed_pool.valid, "valid epoch can recover helper after rejection")
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_debug_flight.gd")
	_check(source.contains("FLIGHT_CPU6_HOOKS_V1") and source.contains("var spheres: Variant = _flight_spheres()"), "installed Variant hook")
	_check(source.contains("_flight_safe_step(direction, requested, spheres)"), "installed virtual safe-step")
	if _failures == 0:
		print("FlightCPU6: PASS packed centre/radius/nearest parity, guard replays=%d, inside recovery, scope/order guards, hooks/scene parse" % guard_checks)
	quit(0 if _failures == 0 else 1)
