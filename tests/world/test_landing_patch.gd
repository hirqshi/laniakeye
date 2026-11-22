extends SceneTree

const Policy = preload("res://game/debug/lk_landing_patch_policy.gd")
const LandingScene = preload("res://scenes/world/test_catalog_landing_patch.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("LandingPatch: FAIL " + label)

func _initialize() -> void:
	_check(Policy.can_prepare(0.5) and Policy.can_prepare(32.5) and Policy.can_prepare(64.0), "preparation height range")
	_check(not Policy.can_prepare(0.0) and not Policy.can_prepare(64.1) and not Policy.can_prepare(INF), "preparation range guards")
	var lattice: LkPosition64 = LkPosition64.new(1.0e12 + 0.375, -2.875, 0.5)
	var point: LkPosition64 = LkPosition64.new(1.0e12 + 70.5, -30.875, 100.5)
	var plan: Dictionary = Policy.plan(point, lattice)
	_check(plan["ok"], "valid plan")
	var anchor: LkPosition64 = plan["anchor"]
	_check(anchor.x == 1.0e12 + 64.375 and anchor.y == -34.875 and anchor.z == 96.5, "double precision lattice rounding")
	_check(anchor.minus(point).length() <= sqrt(3.0) * 16.0 + 1.0e-6, "nearest-grid bound")
	_check(Policy.plan(anchor, lattice)["anchor"].minus(anchor).length() == 0.0, "idempotent snapping")
	_check(not Policy.plan(point, lattice, 0.0)["ok"], "reject invalid grid")
	_check(not Policy.plan(LkPosition64.new(INF, 0.0, 0.0), lattice)["ok"], "reject invalid coordinates")
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_landing_patch.gd")
	_check(source.contains("STAGING_LAYER") and source.contains("get_voxel_f_interpolated") and source.contains("intersect_shape"), "readiness contract present")
	_check(source.contains("_pending_stable_ticks >= 5") and source.contains("_landing_revision"), "stability and revision contracts present")
	if _failures == 0:
		print("LandingPatch: PASS height policy, double lattice, plan bounds, guards, readiness contracts, scene parse")
	print("LandingPatch: CPU/contracts only; staging physics, promotion, remote walking and edit return need visual integration")
	quit(0 if _failures == 0 else 1)
