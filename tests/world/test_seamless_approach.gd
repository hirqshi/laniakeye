extends SceneTree

const Forecast = preload("res://game/debug/lk_surface_approach_forecast.gd")
const Carry = preload("res://game/debug/lk_debug_flight_carry.gd")
const SceneScript = preload("res://scenes/world/test_catalog_seamless_approach.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("SeamlessApproach: FAIL " + label)

func _initialize() -> void:
	var band: Dictionary = Carry.band(6371000.0, 9.81)
	var q: LkPosition64 = LkPosition64.new(2000000.0, 0.0, 0.0)
	var inward: LkPosition64 = LkPosition64.new(-1.0, 0.0, 0.0)
	var vertical: Dictionary = Forecast.predict(q, inward, 1000000.0, 0.0, 1.0, band)
	_check(vertical["ok"] and vertical["predicted"] and vertical["eta_s"] > 0.0, "vertical approach forecast")
	_check(vertical["point"].minus(LkPosition64.new(1000001.0, 0.0, 0.0)).length() < 1.0e-6, "radial target")
	var diagonal: Dictionary = Forecast.predict(LkPosition64.new(0.0, 1100000.0, 0.0), LkPosition64.new(0.2, -1.0, 0.0), 1000000.0, 0.0, 1.0, band)
	_check(diagonal["predicted"] and diagonal["point"].x > 1000.0, "oblique predicts ahead rather than directly below")
	_check(absf(diagonal["point"].length() - 1000001.0) < 1.0e-6, "projected surface radius")
	var miss: Dictionary = Forecast.predict(q, LkPosition64.new(0.0, 1.0, 0.0), 1000000.0, 0.0, 1.0, band)
	_check(miss["ok"] and not miss["predicted"], "miss is radial fallback")
	var hover: Dictionary = Forecast.predict(q, LkPosition64.new(), 1000000.0, 0.0, 1.0, band)
	_check(hover["ok"] and not hover["predicted"], "hover fallback")
	var positive: Dictionary = Forecast.predict(q, inward, 1000000.0, 0.003, 1.0, band)
	var negative: Dictionary = Forecast.predict(q, inward, 1000000.0, -0.003, 1.0, band)
	_check(positive["point"].z > 0.0 and negative["point"].z < 0.0, "rotation sign")
	_check(absf(positive["point"].z + negative["point"].z) < 1.0e-6, "signed rotation symmetry")
	var full: Dictionary = Forecast.predict(LkPosition64.new(1100000.0, 0.0, 0.0), inward, 1000000.0, 0.003, 1.0, band)
	_check(absf(full["drift_s"]) < 1.0e-12 and absf(full["point"].z) < 1.0e-6, "full carry removes geographic drift")
	var faster: Dictionary = Forecast.predict(q, inward, 1000000.0, 0.0, 2.0, band)
	_check(is_equal_approx(faster["eta_s"] * 2.0, vertical["eta_s"]), "manual speed changes time estimate")
	_check(not Forecast.predict(LkPosition64.new(INF, 0.0, 0.0), inward, 1.0, 0.0, 1.0, band)["ok"], "nonfinite guard")
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_auto_surface.gd")
	_check(source.contains("PREFETCH_HOOKS_V1") and source.contains("_prefetch_target_invalid(target, height)"), "base hooks installed")
	if _failures == 0:
		print("SeamlessApproach: PASS vertical/oblique forecast, fallback, spin/carry, ETA scaling, guards, hook installation, scene parse")
	print("SeamlessApproach: actual preload speed, forecast error and A/B landings require in-game testing")
	quit(0 if _failures == 0 else 1)
