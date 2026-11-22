extends SceneTree

const Pool = preload("res://game/debug/lk_flight_sphere_pool.gd")
const FlightMath = preload("res://game/debug/lk_debug_flight_math.gd")
const SceneScript = preload("res://scenes/world/test_catalog_flight_cpu_v4.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("FlightCPU4: FAIL " + label)

func _legacy(states: Dictionary, descriptors: Dictionary, active_id: String, observer: LkPosition64, local_ready: bool) -> Dictionary:
	var active: Array = []
	for state: Dictionary in states["bodies"]:
		if state["id"] == active_id:
			active = state["position_m"]
			break
	var rows: Array = []
	var nearest: float = INF
	var label: String = ""
	for state: Dictionary in states["bodies"]:
		var center: Array = [-observer.x, -observer.y, -observer.z]
		if state["id"] != active_id:
			for axis: int in range(3):
				center[axis] += float(state["position_m"][axis]) - float(active[axis])
		var radius: float = descriptors[state["id"]]["radius_m"]
		var distance: float = sqrt(float(center[0]) * float(center[0]) + float(center[1]) * float(center[1]) + float(center[2]) * float(center[2]))
		var height: float = distance - radius
		if height < nearest:
			nearest = height
			label = String(state["id"]).left(8)
		rows.append({"center": center, "radius": radius + (32.0 if state["id"] != active_id or not local_ready else 0.0)})
	return {"rows": rows, "height": nearest, "label": label}

func _initialize() -> void:
	var star: Dictionary = {"id": "star", "radius_m": 1000000.0}
	var planet: Dictionary = {"id": "planet", "radius_m": 1000.0}
	var moon: Dictionary = {"id": "moon", "radius_m": 100.0}
	var layout: Dictionary = {"layout_version": 1, "system_id": "sphere-fixture", "star": star, "planets": [{"body": planet, "moons": [{"body": moon}]}]}
	var states: Dictionary = {"system_id": "sphere-fixture", "time_s": 12.25, "bodies": [
		{"id": "star", "position_m": [0.0, 0.0, 0.0]},
		{"id": "planet", "position_m": [1.0e12 + 0.125, -3.75, 2.5]},
		{"id": "moon", "position_m": [1.0e12 + 10000000.125, -3.75, 2.5]}]}
	var descriptors: Dictionary = {"star": star, "planet": planet, "moon": moon}
	var original: PackedByteArray = var_to_bytes(states)
	var pool = Pool.new()
	_check(pool.configure(layout, "planet"), "bind metadata")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 430
	var replay_checks: int = 0
	for i: int in range(32):
		var observer: LkPosition64 = LkPosition64.new(1002.0 + float(i) * 0.125, 3.5, -2.0)
		var ready: bool = i % 2 == 0
		var legacy: Dictionary = _legacy(states, descriptors, "planet", observer, ready)
		var rows: Array = pool.build(states, observer, 12.25, ready)
		_check(pool.valid and rows == legacy["rows"], "all centres/radii exactly equal legacy")
		_check(pool.nearest_height == legacy["height"] and pool.nearest_label == legacy["label"], "nearest surface parity")
		_check(rows[1]["center"] == [-observer.x, -observer.y, -observer.z], "active centre avoids astronomical subtraction")
		for j: int in range(12):
			var direction: Vector3 = Vector3(-1.0, 0.0, 0.0) if j == 0 else Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
			var request: float = 1.0e12 if j % 2 == 0 else 100.0
			_check(FlightMath.safe_step(direction, request, rows) == FlightMath.safe_step(direction, request, legacy["rows"]), "unchanged movement guard replay")
			replay_checks += 1
		rows.append({"center": [1.0, 2.0, 3.0], "radius": 1.0})
		_check(pool.build(states, observer, 12.25, ready).size() == 3, "approach-envelope tail does not accumulate")
	_check(var_to_bytes(states) == original, "borrowed state cache is not mutated")
	var near_moon: LkPosition64 = LkPosition64.new(10000101.0, 0.0, 0.0)
	pool.build(states, near_moon, 12.25, false)
	_check(pool.nearest_label == "moon" and pool.nearest_height == 1.0, "nearest foreign body")
	_check(pool.build(states, near_moon, 12.250001, false).is_empty() and not pool.valid, "wrong exact epoch rejected")
	var reordered: Dictionary = states.duplicate(true)
	reordered["bodies"].reverse()
	_check(pool.build(reordered, near_moon, 12.25, false).is_empty() and not pool.valid, "ID order cannot attach wrong radius")
	var invalid: Dictionary = states.duplicate(true)
	invalid["bodies"][2]["position_m"][0] = INF
	_check(pool.build(invalid, near_moon, 12.25, false).is_empty(), "invalid position refused")
	_check(not Pool.new().configure(layout, "missing"), "missing active body refused")
	pool.build(states, near_moon, 12.25, false)
	_check(pool.valid, "valid epoch can recover helper after rejection")
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_debug_flight.gd")
	_check(source.contains("FLIGHT_SPHERE_CPU4_HOOKS_V1") and source.contains("_build_flight_body_spheres(states, local_ready)"), "installed hook")
	_check(source.contains("if _failed:\n\t\treturn # Fail closed before any movement"), "rejected spheres abort commanded movement")
	if _failures == 0:
		print("FlightCPU4: PASS exact centre/radius/nearest parity, guard replays=%d, tail reuse, read-only states, scope/order guards, hook/scene parse" % replay_checks)
	print("FlightCPU4: evaluator unchanged; pool speedup and real A/B route still require Godot game measurements")
	quit(0 if _failures == 0 else 1)
