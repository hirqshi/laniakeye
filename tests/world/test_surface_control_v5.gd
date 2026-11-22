extends SceneTree

const Policy5 = preload("res://game/debug/lk_surface_control_policy.gd")
const FlightMath5 = preload("res://game/debug/lk_debug_flight_math.gd")
const Scene5 = preload("res://scenes/world/test_catalog_surface_control_v5.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("SurfaceControl5: FAIL " + label)

func _initialize() -> void:
	_check(Policy5.classify(0.0, 0.001) == "EVA_ASSIST", "zero acceleration uses assist")
	_check(Policy5.classify(0.00015, 0.001) == "EVA_ASSIST", "rounded HUD zero is not physical zero")
	_check(Policy5.classify(0.000999, 0.001) == "EVA_ASSIST", "weak boundary")
	_check(Policy5.classify(0.001, 0.001) == "NORMAL", "normal boundary")
	_check(Policy5.classify(9.81, 0.001) == "NORMAL", "normal planet unchanged")
	_check(Policy5.classify(NAN, 0.001) == "INVALID" and Policy5.classify(-1.0, 0.001) == "INVALID" and Policy5.classify(1.0, 0.0) == "INVALID", "bad policy inputs rejected")
	_check(Policy5.speed(100000.0, true, 5.0) == 5.0, "assist caps speed")
	_check(Policy5.speed(0.05, true, 5.0) == 0.05, "wheel may reduce speed")
	_check(Policy5.speed(100000.0, false, 5.0) == 100000.0, "cruise unchanged")
	var instance = Scene5.new()
	for height: float in [0.0, 1.0, 32.0, 10000.0]:
		var expected: float = FlightMath5.speed_at_height(height, 2.0)
		_check(instance._flight_speed_at_height(height, 2.0) == expected, "normal virtual speed equals original")
		instance.set("_control5_assisted", true)
		_check(instance._flight_speed_at_height(height, 2.0) == minf(expected, 5.0), "assisted virtual speed")
		instance.set("_control5_assisted", false)
	instance.free()
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_surface_control_v5.gd")
	_check(source.contains("super._try_flight_landing()"), "normal landing chain retained")
	_check(not source.contains("_flight_active = false") and not source.contains("_player.set_physics_process(true)"), "assist never enters physical walking")
	_check(not source.contains("func _tick_flight(") and not source.contains("func _flight_spheres(") and not source.contains("func _update_navigation_tick("), "flight/collision/clock/nav inherited")
	_check(source.contains("_auto4_panel.hide()") and source.contains("AUTO TRANSFER PAUSED:"), "menu closes on selection and pause visible")
	_check(source.contains("PHYSICS STOPPED") and source.contains("%.9f m/s2"), "failure and exact acceleration HUD")
	var base: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_debug_flight.gd")
	_check(base.contains("SURFACE_CONTROL5_SPEED_HOOK_V1") and base.contains("_flight_requested_speed = _flight_speed_at_height("), "installed speed hook")
	var handover: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_transfer_handover_v2.gd")
	_check(handover.contains("TRANSFER_TOOL_REBIND_FIX_V1"), "prior native-owner fix required")
	_check(ResourceLoader.load("res://scenes/world/test_catalog_surface_control_v5.tscn") is PackedScene, "scene resource parses")
	if _failures == 0:
		print("SurfaceControl5: PASS weak/normal policy, speed parity/cap, protected-flight retention, menu/failure HUD, dependencies and scene parse")
	print("SurfaceControl5: stabilized debug assist only, not native physical zero-g or low-g walking proof")
	quit(0 if _failures == 0 else 1)
