extends SceneTree
## Headless test. Run:
## godot --headless --path . --script res://tests/game/test_world_service.gd

const ClockServiceScript = preload("res://game/world/clock_service.gd")
const WorldServiceScript = preload("res://game/world/world_service.gd")
const DefinitionScript = preload("res://game/world/generation/lk_universe_definition.gd")
const ClockStore = preload("res://game/world/runtime/lk_world_clock_store.gd")
const Identity = preload("res://game/world/generation/lk_world_identity.gd")
const Lighting = preload("res://game/world/runtime/lk_stellar_lighting.gd")

var _failures: int = 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("WorldService: PASS")
	else:
		printerr("WorldService: FAIL count=%d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _remove_fixture(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists(path + ".tmp"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path.get_base_dir()))


func _run() -> void:
	var universe: String = Identity.child_id(Identity.universe_id("world-service-test"), "test_fixture", "world_service_v1")
	var path: String = ClockStore.clock_path(universe)
	_remove_fixture(path)

	var clock = ClockServiceScript.new()
	var world = WorldServiceScript.new(DefinitionScript.new(), clock)
	var events: Array = []
	world.activated.connect(func(id: StringName) -> void: events.append("on:" + String(id)))
	world.deactivated.connect(func(id: StringName) -> void: events.append("off:" + String(id)))
	var failures: Array = []
	world.failed.connect(func(reason: String) -> void: failures.append(reason))

	var address_a: Dictionary = WorldServiceScript.make_address(0, 0, 0, 0, 0, 0)
	var address_b: Dictionary = WorldServiceScript.make_address(0, 0, 0, 0, 0, 1)

	_check(not world.has_active(), "no active body at start")
	_check(world.tick(0.016) == 0.0, "tick without a body is a no-op")
	_check(not world.activate(address_a), "activation requires an open clock")
	_check(failures.size() == 1, "failed activation reports once")

	_check(clock.open(universe), "open the fixture clock")
	var context_a: Dictionary = world.resolve(address_a)
	var context_b: Dictionary = world.resolve(address_b)
	_check(not context_a.is_empty() and not context_b.is_empty(), "both addresses resolve")
	if context_a.is_empty() or context_b.is_empty():
		clock.close()
		_remove_fixture(path)
		return
	var id_a: StringName = StringName(context_a["body"]["id"])
	var id_b: StringName = StringName(context_b["body"]["id"])
	_check(id_a != id_b, "different planet slots are different bodies")

	_check(world.activate(address_a), "activate body A")
	_check(world.active_body_id() == id_a, "body A is active")
	_check(world.active_frame.world_time_s == clock.now_s(), "frame is created at the current epoch")
	_check(events == ["on:" + String(id_a)], "first activation emits only activated")

	clock.advance(0.5)
	var step: float = world.tick(999.0)
	_check(absf(step - world.active_frame.angular_speed_rad_s * 0.5) < 1.0e-12, "frame uses the shared elapsed time, not the delta argument")
	_check(world.tick(0.5) == 0.0, "a second tick without clock progress does not advance")

	_check(not world.activate({"galaxy": 0}), "an incomplete address is rejected")
	_check(world.active_body_id() == id_a, "a failed activation keeps the active body")

	_check(world.activate(address_b), "switch to body B")
	_check(events.size() == 3 and events[1] == "off:" + String(id_a) and events[2] == "on:" + String(id_b), "a switch emits deactivated, then activated")
	_check(world.active_frame.world_time_s == clock.now_s(), "B starts at the same epoch")

	clock.advance(10.0)
	_check(world.activate(address_a), "return to body A")
	_check(world.active_frame.world_time_s == clock.now_s(), "A-B-A does not reset the epoch")

	var q: Array = [13000000.0, 0.0, 0.0]
	var light: Dictionary = world.lighting_at(q)
	_check(not light.is_empty() and is_finite(float(light["sin_altitude"])), "lighting is evaluated")
	_check(light == Lighting.evaluate(world.active_context["orbit"], world.active_context["spin"], clock.now_s(), q), "lighting matches a direct evaluation")
	_check(world.lighting_at([1.0]).is_empty(), "an invalid observer gives empty lighting")

	world.deactivate()
	_check(not world.has_active() and world.lighting_at(q).is_empty(), "deactivate clears the body")
	_check(clock.close(), "close the fixture clock")
	_remove_fixture(path)
