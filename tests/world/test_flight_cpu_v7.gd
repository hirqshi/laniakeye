extends SceneTree

const OldPool = preload("res://game/debug/lk_flight_sphere_pool.gd")
const FusedPool = preload("res://game/debug/lk_flight_sphere_pool_fused.gd")
const Occlusion = preload("res://game/debug/lk_navigation_occlusion_scalar.gd")
const Snapshot = preload("res://game/world/rendering/lk_far_body_snapshot.gd")
const Math = preload("res://game/debug/lk_debug_flight_math.gd")
const SceneScript = preload("res://scenes/world/test_catalog_flight_cpu_v7.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("FlightCPU7: FAIL " + label)

func _reference_occluded(records: Array, relative: Array, distance: float, ignore_body: String = "") -> bool:
	if distance < 0.01:
		return false
	var ray: Array = [relative[0] / distance, relative[1] / distance, relative[2] / distance]
	for record: Dictionary in records:
		if record["id"] == ignore_body:
			continue
		var hit: float = Snapshot.ray_distance(record, ray)
		if hit > 0.0 and hit < distance - 2.0:
			return true
	return false

func _initialize() -> void:
	var layout: Dictionary = {"layout_version": 1, "system_id": "cpu7-fixture", "star": {"id": "star", "radius_m": 1.0e6}, "planets": [{"body": {"id": "planet", "radius_m": 1000.0}, "moons": [{"body": {"id": "moon", "radius_m": 100.0}}]}]}
	var states: Dictionary = {"system_id": "cpu7-fixture", "time_s": 12.25, "bodies": [
		{"id": "star", "position_m": [0.0, 0.0, 0.0]},
		{"id": "planet", "position_m": [1.0e12 + 0.125, -3.75, 2.5]},
		{"id": "moon", "position_m": [1.0e12 + 10000000.125, -3.75, 2.5]}]}
	var old = OldPool.new()
	var fused = FusedPool.new()
	_check(old.configure(layout, "planet") and fused.configure(layout, "planet"), "bind")
	var before: PackedByteArray = var_to_bytes(states)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 430
	var guard_checks: int = 0
	for index: int in range(32):
		var observer: LkPosition64 = LkPosition64.new(1002.0 + float(index) * 0.125, 3.5, -2.0)
		var ready: bool = index % 2 == 0
		var expected: Array = old.build(states, observer, 12.25, ready)
		var actual: Array = fused.build(states, observer, 12.25, ready)
		_check(fused.valid and var_to_bytes(expected) == var_to_bytes(actual), "byte-exact sphere rows")
		_check(old.nearest_height == fused.nearest_height and old.nearest_label == fused.nearest_label, "nearest parity")
		# A synthetic parent approach guard must survive consumption unchanged.
		var extra: Dictionary = {"center": [50.0, 0.0, 0.0], "radius": 10.0}
		expected.append(extra.duplicate(true))
		actual.append(extra.duplicate(true))
		for ray_index: int in range(12):
			var direction: Vector3 = Vector3.RIGHT if ray_index == 0 else Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
			_check(Math.safe_step(direction, 1.0e12, expected) == Math.safe_step(direction, 1.0e12, actual), "guard parity with appended approach sphere")
			guard_checks += 1
		_check(fused.build(states, observer, 12.25, ready).size() == 3, "tail pruned before next build")
	_check(var_to_bytes(states) == before, "states never mutated")
	var observer: LkPosition64 = LkPosition64.new(1002.0, 0.0, 0.0)
	var malformed: Dictionary = states.duplicate(true)
	malformed["bodies"][2]["position_m"][0] = INF
	var calls_before: int = fused.calls
	_check(fused.build(malformed, observer, 12.25, true).is_empty() and not fused.valid and fused.calls == calls_before, "late invalid row refuses partial scratch output")
	_check(fused.build(states, observer, 12.26, true).is_empty() and not fused.valid, "exact epoch guard")
	malformed = states.duplicate(true)
	malformed["bodies"].reverse()
	_check(fused.build(malformed, observer, 12.25, true).is_empty() and not fused.valid, "row-order guard")
	_check(not fused.build(states, observer, 12.25, true).is_empty() and fused.valid, "recovery")
	var records: Array[Dictionary] = []
	for index: int in range(264):
		var x: float = rng.randf_range(-1.0, 1.0)
		var y: float = rng.randf_range(-1.0, 1.0)
		var z: float = rng.randf_range(-1.0, 1.0)
		var length: float = sqrt(x * x + y * y + z * z)
		records.append({"id": "body_%03d" % index, "direction": [x / length, y / length, z / length], "radius_relative": 0.0001 + float(index % 5) * 0.001, "distance_m": 50.0 + float(index) * 1000.0})
	var occlusion_checks: int = 0
	for index: int in range(1024):
		var relative: Array = [rng.randf_range(-1.0e6, 1.0e6), rng.randf_range(-1.0e6, 1.0e6), rng.randf_range(-1.0e6, 1.0e6)]
		var distance: float = sqrt(float(relative[0]) * float(relative[0]) + float(relative[1]) * float(relative[1]) + float(relative[2]) * float(relative[2]))
		var ignore: String = "body_%03d" % (index % 264) if index % 2 == 0 else ""
		_check(Occlusion.occluded(records, relative, distance, ignore) == _reference_occluded(records, relative, distance, ignore), "occlusion reference parity")
		occlusion_checks += 1
	for radius: float in [0.0, 0.01, 1.0, 2.0]:
		var edge: Array[Dictionary] = [{"id": "edge", "direction": [0.0, 0.0, 1.0], "radius_relative": radius, "distance_m": 10.0}]
		for distance: float in [0.0, 0.009, 2.0, 10.0, 12.0, 100.0]:
			var relative: Array = [0.0, 0.0, distance]
			_check(Occlusion.occluded(edge, relative, distance) == _reference_occluded(edge, relative, distance), "near/inside/surface edge parity")
	# Verify scene override against actual inherited original implementation.
	var scene = SceneScript.new()
	scene.set("_nav_records", records)
	for index: int in range(8):
		var relative: Array = [100.0, 200.0, 300.0 + float(index)]
		var distance: float = sqrt(10000.0 + 40000.0 + float(relative[2]) * float(relative[2]))
		scene.cpu7_scalar_occlusion_enabled = true
		var fast: bool = scene._nav_occluded(relative, distance)
		scene.cpu7_scalar_occlusion_enabled = false
		_check(fast == scene._nav_occluded(relative, distance), "scene dispatch versus actual parent")
	scene.free()
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_flight_cpu_v7.gd")
	_check(not source.contains("func _flight_spheres(") and not source.contains("func _flight_safe_step(") and not source.contains("func _update_navigation_tick("), "no approach/movement/throttle overrides")
	_check(not source.contains("func _unhandled_input("), "hotkeys inherited unchanged")
	for path: String in ["res://scenes/world/test_catalog_flight_cpu_v7.tscn", "res://scenes/world/test_catalog_flight_cpu_v7_baseline.tscn", "res://scenes/world/test_catalog_flight_cpu_v7_nav_only.tscn", "res://scenes/world/test_catalog_flight_cpu_v7_spheres_only.tscn"]:
		_check(ResourceLoader.load(path) is PackedScene, "scene resource parses: " + path)
	if _failures == 0:
		print("FlightCPU7: PASS spheres byte-exact, guard replays=%d, occlusion rays=%d plus edges, actual parent dispatch, inherited chain structure, all4 scenes parse" % [guard_checks, occlusion_checks])
	quit(0 if _failures == 0 else 1)
