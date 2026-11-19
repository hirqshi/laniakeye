extends SceneTree

const SharedClock = preload("res://world/runtime/lk_world_clock.gd")
const ClockStore = preload("res://world/runtime/lk_world_clock_store.gd")
const SharedFrame = preload("res://world/runtime/lk_clocked_body_frame.gd")
const Context = preload("res://world/runtime/lk_body_context.gd")
const Definition = preload("res://world/generation/lk_universe_definition.gd")
const Identity = preload("res://world/generation/lk_world_identity.gd")
const Motion = preload("res://world/generation/lk_kepler_motion.gd")
const Lighting = preload("res://world/runtime/lk_stellar_lighting.gd")
const VisualScene = preload("res://scenes/world/test_catalog_world_clock.gd")

var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("WorldClock: FAIL " + label)


func _initialize() -> void:
	var clock = SharedClock.new()
	_check(clock.now_s() == 0.0, "new universe starts at zero")
	_check(clock.restore(123456.125), "restore epoch")
	var start: float = clock.now_s()
	_check(not clock.advance(-1.0) and not clock.advance(NAN), "reject invalid delta")
	_check(clock.now_s() == start, "invalid delta leaves epoch unchanged")
	for tick: int in range(600):
		clock.advance(1.0 / 60.0)
	_check(absf(clock.now_s() - start - 10.0) < 1.0e-9, "one owner advances exactly once")
	var definition = Definition.new()
	var a: Dictionary = Context.resolve(definition, 0, 0, 0, 0, 0, 0)
	var b: Dictionary = Context.resolve(definition, 0, 0, 0, 0, 0, 1)
	_check(not a.is_empty() and not b.is_empty(), "two target contexts")
	if a.is_empty() or b.is_empty():
		quit(1)
		return
	var first = SharedFrame.new(StringName(a["body"]["id"]), a["spin"], clock)
	var t: float = clock.now_s()
	_check(first.world_time_s == t, "initial frame created at current epoch")
	clock.advance(0.5)
	var step: float = first.advance(999.0)
	_check(absf(step - first.angular_speed_rad_s * 0.5) < 1.0e-12, "frame uses shared elapsed time not argument")
	_check(first.advance(0.5) == 0.0, "repeated frame sync does not advance time")
	_check(clock.now_s() == t + 0.5, "frame does not own clock")
	var second = SharedFrame.new(StringName(b["body"]["id"]), b["spin"], clock)
	_check(second.world_time_s == clock.now_s(), "B starts at same epoch")
	clock.advance(10.0)
	second.advance(0.0)
	var returned = SharedFrame.new(StringName(a["body"]["id"]), a["spin"], clock)
	_check(returned.world_time_s == clock.now_s(), "A-B-A does not reset")
	var q: LkPosition64 = LkPosition64.new(13000000.0, 0.0, 0.0)
	var axes: Array = Motion.spin_state(a["spin"], clock.now_s())["body_to_system_axes"]
	var expected: LkPosition64 = LkPosition64.new(float(axes[0][0]) * q.x, float(axes[0][1]) * q.x, float(axes[0][2]) * q.x)
	_check(returned.body_to_inertial(q).minus(expected).length() < 1.0e-6, "unloaded body returns in correct phase")
	var light_before: Dictionary = Lighting.evaluate(a["orbit"], a["spin"], clock.now_s(), [q.x, q.y, q.z])
	var orbit_before: Dictionary = Motion.evaluate(a["orbit"], clock.now_s())
	var test_id: String = Identity.child_id(a["universe_id"], "test_fixture", "shared_clock_v1")
	_check(ClockStore.save_clock(test_id, clock), "save isolated clock")
	_check(ClockStore.save_clock(test_id, clock), "replace existing clock file")
	var loaded: Dictionary = ClockStore.load_clock(test_id)
	_check(loaded["ok"], "load clock")
	if loaded["ok"]:
		_check(loaded["found"], "clock found")
		var restored = loaded["clock"]
		_check(restored.now_s() == clock.now_s(), "exact epoch round trip, no offline accrual")
		_check(light_before == Lighting.evaluate(a["orbit"], a["spin"], restored.now_s(), [q.x, q.y, q.z]), "lighting restored")
		_check(orbit_before == Motion.evaluate(a["orbit"], restored.now_s()), "orbit restored")
	var path: String = ClockStore.clock_path(test_id)
	if FileAccess.file_exists(path):
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "remove isolated test clock")
	var missing: Dictionary = ClockStore.load_clock(test_id)
	_check(missing["ok"] and not missing["found"], "missing clock starts new epoch")
	_check(not ClockStore.load_clock("invalid")["ok"], "reject invalid namespace")
	print("WorldClock: epoch=%.6f body_a=%s body_b=%s" % [clock.now_s(), a["body"]["id"], b["body"]["id"]])
	if _failures == 0:
		print("WorldClock: PASS single owner, switch continuity, initial phase, orbit/light restore, persistence, scene parse")
	quit(0 if _failures == 0 else 1)
