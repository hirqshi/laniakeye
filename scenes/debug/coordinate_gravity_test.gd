extends Node3D

var _lines: PackedStringArray = []
var _failures: int = 0

func _check(label: String, success: bool) -> void:
	var line: String = ("PASS " if success else "FAIL ") + label
	_lines.append(line)
	print(line)
	if not success:
		_failures += 1
		push_error(line)

func _ready() -> void:
	var earth_center: LkPosition64 = LkPosition64.new(150000000000.0, 0.0, 0.0)
	var earth: LkGravityBody = LkGravityBody.new(&"earth", earth_center, 6371000.0, 398600441800000.0)
	var surface: LkPosition64 = earth_center.plus(LkPosition64.new(0.0, earth.radius_m, 0.0))
	var gravity: LkGravityService = LkGravityService.new()
	gravity.bodies.append(earth)
	var sample: Dictionary = gravity.sample(surface)
	var acceleration: Vector3 = sample["acceleration"]
	var up: Vector3 = sample["up"]
	var expected_g: float = earth.mu_m3_s2 / (earth.radius_m * earth.radius_m)
	_check("surface gravity", absf(acceleration.length() - expected_g) < 0.00001)
	_check("radial up", up.dot(Vector3.UP) > 0.99999)
	_check("center has no undefined up", not bool(gravity.sample(earth_center)["has_up"]))
	var moon_center: LkPosition64 = earth_center.plus(LkPosition64.new(384400000.0, 0.0, 0.0))
	var moon: LkGravityBody = LkGravityBody.new(&"moon", moon_center, 1737400.0, 4904869500000.0)
	gravity.bodies.append(moon)
	var moon_surface: LkPosition64 = moon_center.plus(LkPosition64.new(0.0, moon.radius_m, 0.0))
	_check("earth dominates near earth", gravity.sample(surface)["dominant_id"] == &"earth")
	_check("moon dominates near moon", gravity.sample(moon_surface, &"earth")["dominant_id"] == &"moon")
	var moon_sample: Dictionary = gravity.sample(moon_surface)
	var combined: Vector3 = moon_sample["acceleration"]
	_check("gravity sums both bodies", combined.is_equal_approx(earth.acceleration_at(moon_surface) + moon.acceleration_at(moon_surface)))
	var frame: LkCoordinateFrame = LkCoordinateFrame.new()
	frame.threshold_m = 64.0
	_check("initialize frame", frame.initialize_origin(surface))
	var tiny: LkPosition64 = surface.plus(LkPosition64.new(0.01, 0.02, -0.03))
	var round_trip: LkPosition64 = frame.to_absolute(frame.to_local(tiny))
	_check("centimeter round trip at 150 billion meters", round_trip.minus(tiny).length() < 0.0001)
	var actor: Node3D = Node3D.new()
	var landmark: Node3D = Node3D.new()
	add_child(actor)
	add_child(landmark)
	actor.position = Vector3(1.0, 2.0, 3.0)
	landmark.position = Vector3(17.0, -6.0, 5.0)
	_check("register independent roots", frame.register_root(actor) and frame.register_root(landmark))
	var landmark_absolute: LkPosition64 = frame.to_absolute(landmark.global_position)
	var actor_expected: LkPosition64 = frame.to_absolute(actor.global_position)
	var largest_error: float = 0.0
	var shifts: int = 0
	for i: int in range(1024):
		actor.position.x += 17.125
		actor_expected = actor_expected.plus(LkPosition64.new(17.125, 0.0, 0.0))
		if frame.maybe_shift(actor.global_position):
			shifts += 1
		largest_error = maxf(largest_error, frame.to_absolute(actor.global_position).minus(actor_expected).length())
		largest_error = maxf(largest_error, frame.to_absolute(landmark.global_position).minus(landmark_absolute).length())
	_check("repeated shifts preserve absolute positions", shifts > 100 and largest_error < 0.001)
	_check("actor remains near origin", actor.global_position.length() < 65.0)
	var before: LkPosition64 = frame.to_absolute(actor.global_position)
	frame.shift_by(Vector3(-23.5, 10.0, -7.0))
	_check("3-axis shift preserves absolute position", frame.to_absolute(actor.global_position).minus(before).length() < 0.001)
	_lines.append("Shifts: %d | max error: %.9f m" % [shifts, largest_error])
	_lines.append("RESULT: %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	_lines.append("Math/Node3D smoke test only. No voxel, collision or orbit integration yet.")
	var canvas: CanvasLayer = CanvasLayer.new()
	var label: Label = Label.new()
	label.position = Vector2(16.0, 16.0)
	label.add_theme_font_size_override("font_size", 16)
	label.text = "Coordinate / gravity foundation v1\n\n" + "\n".join(_lines)
	canvas.add_child(label)
	add_child(canvas)
	print(_lines[_lines.size() - 2])
