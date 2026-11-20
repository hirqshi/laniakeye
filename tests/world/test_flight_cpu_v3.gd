extends SceneTree

const Cache = preload("res://world/debug/lk_flight_cpu_state_cache.gd")
const Policy = preload("res://world/debug/lk_flight_cpu_policy.gd")
const Layout = preload("res://world/generation/lk_safe_orbit_layout.gd")
const Snapshot = preload("res://world/rendering/lk_far_body_snapshot.gd")
const SceneScript = preload("res://scenes/world/test_catalog_flight_cpu_v3.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("FlightCPU3: FAIL " + label)

func _fixture() -> Dictionary:
	return {"layout_version": 1, "system_id": "cpu-cache-fixture", "epoch_s": 0.0,
		"star": {"id": "star", "kind": "star", "radius_m": 1000000.0},
		"planets": [{"body": {"id": "planet", "parent_id": "star", "kind": "planet", "radius_m": 1000.0, "family": "rocky"},
		"orbit": {"semi_major_axis_m": 100000000.0, "eccentricity": 0.1, "primary_mu_m3_s2": 1.0e15, "inclination_rad": 0.1, "ascending_node_rad": 0.3, "argument_of_periapsis_rad": 0.2, "mean_anomaly_at_epoch_rad": 0.7},
		"spin": {"period_s": 1000.0, "direction": 1.0, "axis_tilt_to_system_y_rad": 0.2, "pole_azimuth_rad": 0.3, "phase_at_epoch_rad": 0.4}, "moons": []}]}

func _initialize() -> void:
	var layout: Dictionary = _fixture()
	var cache = Cache.new()
	_check(cache.configure(layout) and cache.matches(layout.duplicate(true)), "scope fingerprint parity")
	var first: Dictionary = cache.get_states(12.0)
	_check(first == Layout.evaluate(layout, 12.0) and first["bodies"].size() == 2, "exact evaluator parity")
	cache.get_states(12.0)
	_check(cache.builds == 1 and cache.hits == 1, "same epoch hit")
	var second: Dictionary = cache.get_states(12.000001)
	_check(cache.builds == 2 and second["time_s"] == 12.000001, "no epoch quantization")
	_check(first["bodies"][1]["position_m"] != second["bodies"][1]["position_m"], "new physics time actually evaluated")
	var before: Dictionary = second.duplicate(true)
	var observer: LkPosition64 = LkPosition64.new(1002.0, 0.0, 0.0)
	var direct: Array[Dictionary] = Snapshot.build(layout, "planet", observer, 12.000001)
	var shared: Array[Dictionary] = Snapshot.build(layout, "planet", observer, 12.000001, second)
	_check(direct == shared and not shared.is_empty(), "provided snapshot matches original path")
	_check(second == before, "snapshot consumer does not mutate borrowed states")
	cache.invalidate()
	cache.get_states(12.000001)
	_check(cache.builds == 3, "explicit invalidation")
	_check(cache.get_states(INF).is_empty(), "invalid time refused")
	var changed: Dictionary = layout.duplicate(true)
	changed["planets"][0]["orbit"]["inclination_rad"] = 0.5
	_check(not cache.matches(changed), "same system id with changed orbit rejected at bind")
	_check(Policy.navigation_due(0.0, 30.0, true), "marker action forces update")
	_check(not Policy.navigation_due(0.01, 30.0, false) and Policy.navigation_due(0.034, 30.0, false), "cosmetic cadence")
	var paths: Dictionary = {"res://scenes/world/test_catalog_debug_flight.gd": "FLIGHT_CPU3_HOOKS_V1", "res://scenes/world/test_catalog_debug_navigation.gd": "NAV_CPU3_PROVIDER_V1", "res://world/rendering/lk_far_body_snapshot.gd": "SNAPSHOT_CPU3_OPTIONAL_STATES_V1", "res://world/rendering/lk_catalog_far_mesh.gd": "FARMESH_CPU3_PROVIDER_V1"}
	for path: String in paths:
		_check(FileAccess.get_file_as_string(path).contains(paths[path]), "installed hook " + path)
	if _failures == 0:
		print("FlightCPU3: PASS exact state/time parity, shared snapshot, scope binding, invalidation, cosmetic cadence, installed hooks, scene parse")
	print("FlightCPU3: no collision frequency reduction; actual CPU saving and UI smoothness need in-game A/B")
	quit(0 if _failures == 0 else 1)
