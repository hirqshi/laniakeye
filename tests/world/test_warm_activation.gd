extends SceneTree

const Policy = preload("res://world/debug/lk_warm_activation_policy.gd")
const SceneScript = preload("res://scenes/world/test_catalog_approach_activation_fix.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("ActivationGuard: FAIL " + label)

func _initialize() -> void:
	_check(Policy.action(2000.0, 80.0, true, 1024.0, 100.0) == "WAIT_HEIGHT", "legitimate high-altitude hold")
	_check(Policy.action(100.0, 48.0, true, 1024.0, 0.0) == "ALIGN_OR_VALIDATE", "activation distance boundary")
	_check(Policy.action(100.0, 80.0, true, 1024.0, 0.1) == "SETTLE_TARGET", "short mismatch grace")
	_check(Policy.action(100.0, 80.0, true, 1024.0, 0.3) == "RECENTER", "48-to128m dead-zone recovery")
	_check(Policy.action(100.0, 200.0, false, 1024.0, 0.3) == "RETARGET", "outside reusable region")
	for gap: float in [48.001, 49.0, 60.0, 80.0, 96.0, 127.0, 128.0, 129.0]:
		for reusable: bool in [true, false]:
			var result: String = Policy.action(100.0, gap, reusable, 1024.0, 1.0)
			_check(result in ["RECENTER", "RETARGET"], "no indefinite near-ground distance hold")
	var recovered: bool = false
	for tick: int in range(60):
		if Policy.action(100.0, 80.0, true, 1024.0, float(tick) / 60.0) == "RECENTER":
			recovered = true
			_check(tick <= 16, "bounded recovery grace")
			break
	_check(recovered, "stationary 92s case recovers rather than looping")
	_check(Policy.action(100.0, 0.0, true, 1024.0, 0.0) == "ALIGN_OR_VALIDATE", "recenter then align")
	_check(Policy.action(INF, 0.0, true, 1024.0, 0.0) == "INVALID", "invalid geometry refused")
	var anchor: LkPosition64 = LkPosition64.new(1.0e12 + 0.125, 0.0, 0.0)
	_check(Policy.reusable(LkPosition64.new(1.0e12 + 80.125, 0.0, 0.0), anchor), "nearby anchor reuse scalar precision")
	_check(not Policy.reusable(LkPosition64.new(1.0e12 + 97.125, 0.0, 0.0), anchor), "landing-anchor limit retained")
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_approach_activation_fix.gd")
	_check(source.contains("_auto_warm = false") and source.contains("_pending_stable_ticks = 0"), "recenter invalidates readiness")
	_check(source.contains("_auto_elapsed = 0.0") and source.contains("_warm_request_total_s"), "epoch timeout reset and total retained")
	if _failures == 0:
		print("ActivationGuard: PASS height/distance policy, dead-zone recovery, bounded grace, reuse limits, epoch contracts, scene parse")
	print("ActivationGuard: native collider revalidation and real landing require integration; no physics checks bypassed")
	quit(0 if _failures == 0 else 1)
