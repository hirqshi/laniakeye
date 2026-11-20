extends SceneTree

const Policy = preload("res://world/debug/lk_auto_surface_policy.gd")
const AutoScene = preload("res://scenes/world/test_catalog_auto_surface.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("AutoSurface: FAIL " + label)

func _initialize() -> void:
	_check(Policy.should_start(3000.0, 100.0, 10000.0), "30s descent lead")
	_check(not Policy.should_start(4000.0, 100.0, 10000.0), "outside lead and hover zones")
	_check(Policy.should_start(1000.0, 0.0, 10000.0), "hover fallback")
	_check(not Policy.should_start(1000.0, -50.0, 10000.0), "ascending does not start")
	_check(not Policy.should_start(20000.0, 10000.0, 10000.0), "maximum height")
	_check(not Policy.should_start(INF, 10.0, 10000.0), "finite height")
	_check(not Policy.should_start(1000.0, 10.0, 10000.0, 0.0), "invalid time horizon")
	var fixed: LkPosition64 = LkPosition64.new(1.0e9, 2.0e9, -3.0e9)
	var result: Dictionary = Policy.surface_target(fixed, 6371000.0)
	_check(result["ok"], "target projection")
	var target: LkPosition64 = result["point"]
	_check(absf(target.length() - 6371001.0) < 1.0e-6, "target at sphere plus1m")
	_check(absf(target.x / fixed.x - target.z / fixed.z) < 1.0e-15, "direction retained")
	_check(not Policy.surface_target(LkPosition64.new(), 1000.0)["ok"], "zero position rejected")
	_check(Policy.in_target(target, target.plus_local(Vector3(31.0, 0.0, 0.0)), 32.0), "target stability radius")
	_check(not Policy.in_target(target, target.plus_local(Vector3(97.0, 0.0, 0.0)), 96.0), "target invalidation radius")
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_auto_surface.gd")
	_check(source.contains("VoxelViewer.new()") and source.contains("Transform3D.IDENTITY"), "dedicated local prefetch viewer")
	_check(source.contains("STAGING_LAYER") and source.contains("WORLD READY") and source.contains("_pending_stable_ticks >= 5"), "world readiness contract")
	_check(source.contains("auto_surface_enabled") and source.contains("KEY_L"), "independent auto toggle")
	if _failures == 0:
		print("AutoSurface: PASS lead-time policy, hover/height guards, scalar surface target, hysteresis radii, scene parse")
	print("AutoSurface: CPU/contracts only; sandbox/world alignment, actual speedup, moving targets and landing need integration")
	quit(0 if _failures == 0 else 1)
