extends SceneTree
## Headless test. Run:
## godot --headless --path . --script res://tests/game/test_space.gd

const Position64Script = preload("res://game/space/position64.gd")
const CoordinateFrameScript = preload("res://game/space/coordinate_frame.gd")
const RotatingFrameScript = preload("res://game/space/rotating_frame.gd")
const GravityBodyScript = preload("res://game/space/gravity_body.gd")
const GravityServiceScript = preload("res://game/space/gravity_service.gd")

var _failures: int = 0


func _init() -> void:
	_test_position64()
	_test_coordinate_frame()
	_test_rotating_frame()
	_test_gravity_service()
	if _failures == 0:
		print("Space: PASS")
	else:
		printerr("Space: FAIL count=%d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _test_position64() -> void:
	var a: LkPosition64 = LkPosition64.new(1.0e9, 2.0e9, 3.0e9)
	var b: LkPosition64 = LkPosition64.new(1.0e9, 2.0e9, 3.0e9)
	_check(a.plus(b).x == 2.0e9 and a.plus(b).y == 4.0e9 and a.plus(b).z == 6.0e9, "plus adds components")
	_check(a.minus(b).x == 0.0 and a.minus(b).y == 0.0 and a.minus(b).z == 0.0, "minus subtracts components")
	var offset: Vector3 = Vector3(10.0, 20.0, 30.0)
	var sum: LkPosition64 = a.plus_local(offset)
	_check(sum.x == 1.0e9 + 10.0 and sum.y == 2.0e9 + 20.0 and sum.z == 3.0e9 + 30.0, "plus_local adds a local offset")
	_check(absf(sum.length_squared() - (sum.x * sum.x + sum.y * sum.y + sum.z * sum.z)) < 1.0e-6, "length_squared matches components")
	_check(absf(sum.length() - sqrt(sum.length_squared())) < 1.0e-6, "length matches length_squared")
	var dir: Vector3 = sum.direction()
	_check(absf(dir.length() - 1.0) < 1.0e-6, "direction is normalized")
	var rel: Vector3 = sum.relative_to(a)
	_check(rel == offset, "relative_to returns a local offset")
	_check(a.copy() != a, "copy returns a new object")
	_check(a.copy().x == a.x and a.copy().y == a.y and a.copy().z == a.z, "copy preserves components")


func _test_coordinate_frame() -> void:
	var frame: LkCoordinateFrame = LkCoordinateFrame.new()
	frame.threshold_m = 512.0
	var origin: LkPosition64 = LkPosition64.new(1.0e9, 0.0, 0.0)
	_check(frame.initialize_origin(origin), "initialize_origin accepts a value")
	var local: Vector3 = Vector3(100.0, 200.0, 300.0)
	var absolute: LkPosition64 = frame.to_absolute(local)
	_check(absolute.x == 1.0e9 + 100.0 and absolute.y == 200.0 and absolute.z == 300.0, "to_absolute adds the origin")
	var back: Vector3 = frame.to_local(absolute)
	_check(back == local, "to_local inverts to_absolute")
	var root: Node3D = Node3D.new()
	root.name = "SpaceTestRoot"
	get_root().add_child(root)
	_check(frame.register_root(root), "register_root accepts a live root")
	_check(frame.register_root(root), "register_root is idempotent")
	var child: Node3D = Node3D.new()
	root.add_child(child)
	_check(not frame.register_root(child), "register_root rejects a child of a registered root")
	root.global_position = Vector3(600.0, 0.0, 0.0)
	var shifts: Array = []
	frame.shifted.connect(func(delta: Vector3) -> void: shifts.append(delta))
	_check(frame.maybe_shift(Vector3(600.0, 0.0, 0.0)), "maybe_shift triggers beyond the threshold")
	_check(shifts.size() == 1, "shifted emits once")
	_check(root.global_position.x == 0.0, "root is moved back by the shift")
	_check(frame.get_origin().x == 1.0e9 + 600.0, "origin moves forward by the shift")
	_check(frame.to_absolute(Vector3.ZERO).x == 1.0e9 + 600.0, "to_absolute uses the new origin")
	frame.unregister_root(root)
	_check(not frame.maybe_shift(Vector3(1000.0, 0.0, 0.0)), "maybe_shift without roots does nothing")
	root.queue_free()


func _test_rotating_frame() -> void:
	var center: LkPosition64 = LkPosition64.new(1.0e9, 0.0, 0.0)
	var frame: LkRotatingFrame = LkRotatingFrame.new(&"body", center, Vector3(0.0, 1.0, 0.0), 0.1, 0.0)
	_check(frame.get_axis() == Vector3(0.0, 1.0, 0.0), "axis is normalized")
	var step: float = frame.advance(0.5)
	_check(absf(step - 0.05) < 1.0e-12, "advance returns the step angle")
	_check(absf(frame.angle_rad - 0.05) < 1.0e-12, "angle advances by the step")
	var basis: Basis = frame.planet_basis()
	_check(absf(basis.get_scale().length() - 1.0) < 1.0e-6, "planet_basis preserves unit scale")
	var rel: LkPosition64 = LkPosition64.new(100.0, 0.0, 0.0)
	var displaced: LkPosition64 = frame.rotate(rel, 0.05)
	_check(absf(displaced.length() - rel.length()) < 1.0e-9, "rotate preserves length")
	var carry: Vector3 = frame.carry_displacement(rel, 0.05)
	_check(carry.length() > 0.0, "carry_displacement is nonzero for a nonzero radius")
	var velocity: Vector3 = frame.surface_velocity(rel)
	_check(absf(velocity.length() - 0.1 * 100.0) < 1.0e-9, "surface_velocity equals omega cross r")
	var inertial: Vector3 = frame.to_inertial_velocity(Vector3.ZERO, rel)
	_check(inertial == velocity, "zero relative velocity becomes surface velocity")
	var relative: Vector3 = frame.to_relative_velocity(velocity, rel)
	_check(relative.length() < 1.0e-9, "surface velocity converts back to zero relative velocity")


func _test_gravity_service() -> void:
	var service: LkGravityService = LkGravityService.new()
	var center: LkPosition64 = LkPosition64.new(0.0, 0.0, 0.0)
	var body: LkGravityBody = LkGravityBody.new(&"planet", center, 1000.0, 1.0e12)
	service.bodies.append(body)
	var point: LkPosition64 = LkPosition64.new(2000.0, 0.0, 0.0)
	var sample: Dictionary = service.sample(point)
	_check(sample["has_up"], "single body has up")
	_check(sample["dominant_id"] == &"planet", "single body is dominant")
	_check(absf(sample["acceleration"].length() - 1.0e12 / (2000.0 * 2000.0)) < 1.0e-6, "acceleration follows inverse square law")
	_check(sample["up"].x < 0.0, "up points toward the body")
	var center_b: LkPosition64 = LkPosition64.new(10000.0, 0.0, 0.0)
	var body_b: LkGravityBody = LkGravityBody.new(&"moon", center_b, 500.0, 1.0e13)
	service.bodies.append(body_b)
	var sample_b: Dictionary = service.sample(point, &"planet", 1.1)
	_check(sample_b["dominant_id"] == &"moon", "stronger body becomes dominant")
	_check(sample_b["has_up"], "two bodies still have up")
	var zero: Dictionary = service.sample(LkPosition64.new(0.0, 0.0, 0.0))
	_check(not zero["has_up"] and zero["up"] == Vector3.ZERO, "zero acceleration has no up")
