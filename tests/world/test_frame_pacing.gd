extends SceneTree

const Samples = preload("res://world/debug/lk_frame_pacing_samples.gd")
const SceneScript = preload("res://scenes/world/test_catalog_frame_pacing.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("FramePacing: FAIL " + label)

func _initialize() -> void:
	var samples = Samples.new(100)
	for i: int in range(1, 101):
		samples.add("BUILD", float(i))
	var report: Dictionary = samples.summary("BUILD")
	_check(report["n"] == 100 and report["seen"] == 100, "sample count")
	_check(report["mean_ms"] == 50.5 and report["p95_ms"] == 95.0 and report["p99_ms"] == 99.0 and report["max_ms"] == 100.0, "nearest-rank percentiles")
	for i: int in range(100):
		samples.add("BUILD", 10.0)
	report = samples.summary("BUILD")
	_check(report["n"] == 100 and report["seen"] == 200 and report["p99_ms"] == 10.0, "bounded rolling window")
	samples.add("BUILD", INF)
	samples.add("BUILD", -1.0)
	_check(samples.summary("BUILD")["seen"] == 200, "invalid samples rejected")
	samples.add("WALK", 16.0)
	_check(samples.summary("WALK")["n"] == 1 and samples.summary("MISSING").is_empty(), "state isolation")
	_check(Samples.allow_growth(16.0, 0.0, 16.667, 0), "healthy frame allows growth")
	_check(not Samples.allow_growth(30.0, 0.0, 16.667, 0), "slow frame holds growth")
	_check(not Samples.allow_growth(16.0, 0.0, 16.667, 65), "queue pressure holds growth")
	_check(Samples.allow_growth(30.0, 30.0, 16.667, 0), "slower baseline not permanent lock")
	_check(Samples.allow_growth(16.0, 0.0, 16.667, -1), "unknown native queue uses frame gate")
	var base: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_auto_surface.gd")
	_check(base.contains("FRAME_PACING_VIEW_HOOK_V1") and base.contains("_terrain.view_distance = _prefetch_promoted_view_distance()"), "view hook actually installed")
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_frame_pacing.gd")
	_check(source.contains("_auto_warm and not _auto_aligning") and source.contains("super._poll_auto_surface(elapsed)"), "warm-only cadence with accumulated time")
	if _failures == 0:
		print("FramePacing: PASS bounded samples, percentiles, state isolation, growth gates, warm cadence contracts, scene parse")
	print("FramePacing: actual FPS improvement and native task budgets require in-game A/B measurement")
	quit(0 if _failures == 0 else 1)
