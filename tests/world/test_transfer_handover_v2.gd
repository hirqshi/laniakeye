extends SceneTree

const TransferMath2 = preload("res://world/debug/lk_transfer_frame_math.gd")
const OriginalLight2 = preload("res://world/runtime/lk_stellar_lighting.gd")
const Motion2 = preload("res://world/generation/lk_kepler_motion.gd")
const Scene2 = preload("res://scenes/world/test_catalog_transfer_handover_v2.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("Transfer2: FAIL " + label)

func _initialize() -> void:
	var a: Array = [1.0e12 + 0.125, -2.0e11 + 0.25, 6.0e10]
	var b: Array = [-3.0e12 + 0.5, 8.0e11, -7.0e10]
	var states: Dictionary = {"system_id": "fixture", "time_s": 12.25, "bodies": [{"id": "a", "position_m": a}, {"id": "b", "position_m": b}]}
	var saved: PackedByteArray = var_to_bytes(states)
	var observer_a: LkPosition64 = LkPosition64.new(float(b[0]) - float(a[0]) + 5000000.125, float(b[1]) - float(a[1]) + 500.25, float(b[2]) - float(a[2]) - 3.5)
	var result: Dictionary = TransferMath2.rebase(states, "a", "b", observer_a, 12.25)
	_check(result["ok"], "rebase")
	var observer_b: LkPosition64 = result["observer"]
	_check(observer_b.x == 5000000.125 and observer_b.y == 500.25 and observer_b.z == -3.5, "small body offset survives astronomical translation")
	_check(result["roundtrip_error_m"] <= 0.02 and result["system_error_m"] <= 0.02, "measured continuity bounds")
	var back: Dictionary = TransferMath2.rebase(states, "b", "a", observer_b, 12.25)
	var restored: LkPosition64 = back["observer"]
	_check(restored.x == observer_a.x and restored.y == observer_a.y and restored.z == observer_a.z, "return to departure coordinates")
	_check(not TransferMath2.rebase(states, "a", "b", observer_a, 12.250001)["ok"], "exact epoch")
	_check(not TransferMath2.rebase(states, "a", "missing", observer_a, 12.25)["ok"], "missing body")
	_check(not TransferMath2.rebase(states, "a", "a", observer_a, 12.25)["ok"], "same body refused")
	_check(var_to_bytes(states) == saved, "state snapshot read-only")
	var orbit: Dictionary = {"semi_major_axis_m": 1.0e10, "eccentricity": 0.2, "primary_mu_m3_s2": 1.0e20, "mean_anomaly_at_epoch_rad": 0.3, "ascending_node_rad": 0.4, "inclination_rad": 0.2, "argument_of_periapsis_rad": 0.7}
	var spin: Dictionary = {"period_s": 3600.0, "direction": -1.0, "phase_at_epoch_rad": 0.6, "axis_tilt_to_system_y_rad": 0.5, "pole_azimuth_rad": 0.8}
	var q: Array = [1000000.125, 2000000.5, -300000.25]
	for epoch: float in [-1000.0, 0.0, 12400.0, 1.0e9]:
		var light_state: Dictionary = {"position_m": Motion2.evaluate(orbit, epoch)["position_m"], "body_to_system_axes": Motion2.spin_state(spin, epoch)["body_to_system_axes"]}
		_check(var_to_bytes(TransferMath2.lighting(light_state, q)) == var_to_bytes(OriginalLight2.evaluate(orbit, spin, epoch, q)), "full-state light matches old planetary formula")
	var identity: Array = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
	var moon: Dictionary = {"position_m": [1000.0, 0.0, 0.0], "body_to_system_axes": identity}
	var illumination: Dictionary = TransferMath2.lighting(moon, [10.0, 0.0, 0.0])
	_check(illumination["distance_m"] == 1010.0 and illumination["to_star_system"][0] == -1.0, "moon uses full global position")
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_transfer_handover_v2.gd")
	_check(not source.contains("func _tick_flight(") and not source.contains("func _flight_spheres(") and not source.contains("func _try_flight_landing(") and not source.contains("func _update_navigation_tick("), "flight/collision/landing/nav chains not overridden")
	_check(source.contains("_save_journal()") and source.contains("_handover_rollback"), "save preflight and adapter rollback")
	_check(source.contains("live_surface_ready=false") and source.contains("HANDOVER_MIN_HEIGHT_M: float = 10000.0"), "no sandbox-ready to live-ready shortcut")
	_check(not source.contains("KEY_F8") and not source.contains("KEY_F6") and not source.contains("KEY_F7"), "no new F-key shortcuts")
	_check(ResourceLoader.load("res://scenes/world/test_catalog_transfer_handover_v2.tscn") is PackedScene, "scene parses")
	var instance = Scene2.new()
	instance.free()
	if _failures == 0:
		print("Transfer2: PASS frame translation/return, measured error bounds, exact epoch, full-state lighting parity, chain structure, scene parse")
	print("Transfer2: actual handover/AUTO landing/edits/return require in-game acceptance; no native integration run here")
	quit(0 if _failures == 0 else 1)
