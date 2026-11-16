extends Node3D

const PLANET_RADIUS_M: float = 200.0
const SURFACE_G: float = 9.8
const SHIFT_THRESHOLD_M: float = 64.0
const PLANET_ROTATION_RAD_S: float = 0.03
const CARRY_LIMIT_M: float = PLANET_RADIUS_M + 500.0
const STAND_SETTLE_S: float = 2.0
const STAND_GATE_S: float = 30.0
const STAND_TOLERANCE_M: float = 0.02

var _frame: LkCoordinateFrame
var _gravity: LkGravityService
var _rotation: LkRotatingFrame
var _center: LkPosition64
var _planet: StaticBody3D
var _player: LkPlayerController
var _label: Label
var _shifts: int = 0
var _start_absolute: LkPosition64

var _stand_settle_s: float = 0.0
var _stand_time_s: float = 0.0
var _stand_has_ref: bool = false
var _stand_ref: LkPosition64
var _stand_drift_m: float = 0.0
var _stand_max_drift_m: float = 0.0
var _stand_reported: bool = false


func _ready() -> void:
	process_physics_priority = -100

	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.05, 0.09)
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	add_child(sun)

	var dir: Vector3 = Vector3(0.7071, 0.7071, 0.0)
	_center = LkPosition64.new(149597870700.0, 0.0, 0.0)
	var spawn_distance: float = PLANET_RADIUS_M + 2.0
	_start_absolute = LkPosition64.new(_center.x + dir.x * spawn_distance, _center.y + dir.y * spawn_distance, _center.z + dir.z * spawn_distance)

	_frame = LkCoordinateFrame.new()
	_frame.threshold_m = SHIFT_THRESHOLD_M
	_frame.initialize_origin(_start_absolute)
	_frame.shifted.connect(func(_delta: Vector3) -> void: _shifts += 1)

	_gravity = LkGravityService.new()
	_gravity.bodies.append(LkGravityBody.new(&"test_planet", _center, PLANET_RADIUS_M, SURFACE_G * PLANET_RADIUS_M * PLANET_RADIUS_M))
	_rotation = LkRotatingFrame.new(&"test_planet", _center, Vector3.UP, PLANET_ROTATION_RAD_S)

	_planet = StaticBody3D.new()
	_planet.name = "TestPlanet"
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = PLANET_RADIUS_M
	shape.shape = sphere_shape
	_planet.add_child(shape)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = PLANET_RADIUS_M
	sphere_mesh.height = PLANET_RADIUS_M * 2.0
	sphere_mesh.radial_segments = 128
	sphere_mesh.rings = 64
	mesh.mesh = sphere_mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.45, 0.3)
	mesh.material_override = material
	_planet.add_child(mesh)
	for i: int in range(24):
		var y: float = 1.0 - (float(i) + 0.5) / 12.0
		var ring: float = sqrt(maxf(0.0, 1.0 - y * y))
		var angle: float = float(i) * 2.399963
		var marker_dir: Vector3 = Vector3(cos(angle) * ring, y, sin(angle) * ring).normalized()
		var marker: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(3.0, 3.0, 3.0)
		marker.mesh = box
		marker.transform = Transform3D(Basis(Quaternion(Vector3.UP, marker_dir)), marker_dir * PLANET_RADIUS_M)
		_planet.add_child(marker)
	_planet.position = _frame.to_local(_center)
	add_child(_planet)

	_player = LkPlayerController.new()
	_player.name = "Player"
	_player.collision_layer = 2
	_player.collision_mask = 1
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var player_shape: CollisionShape3D = CollisionShape3D.new()
	player_shape.shape = capsule
	_player.add_child(player_shape)
	var pivot: Node3D = Node3D.new()
	pivot.position.y = 0.65
	_player.add_child(pivot)
	var camera: Camera3D = Camera3D.new()
	camera.near = 0.05
	camera.far = 2000.0
	pivot.add_child(camera)
	_player.camera_pivot = pivot
	_player.player_camera = camera
	_player.setup(_frame, _gravity)
	_player.position = Vector3.ZERO
	add_child(_player)
	_player.attach_to_frame(_rotation)
	_frame.register_root(_planet)

	var canvas: CanvasLayer = CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	canvas.add_child(_label)
	add_child(canvas)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("LkPlayerTest: rotating planet. WASD, mouse, Space, Shift, Esc. Stand still %.0f s for the drift gate" % STAND_GATE_S)


func _physics_process(delta: float) -> void:
	# Order inside one tick: frame advance -> planet basis -> player carry.
	# The player's own _physics_process (priority 0) runs after this.
	var step: float = _rotation.advance(delta)
	_planet.global_transform = Transform3D(_rotation.planet_basis(), _planet.global_position)
	_player.carry_with_frame(_rotation, step, CARRY_LIMIT_M)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _fixed_position() -> LkPosition64:
	var rel: LkPosition64 = _rotation.relative_position(_frame.get_origin(), _player.global_position)
	return _rotation.rotate(rel, -_rotation.angle_rad)


func _update_stand_gate(delta: float) -> void:
	var active: bool = (
		Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_back")
		or Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")
		or Input.is_action_pressed("jump")
	)
	if active or not _player.is_on_floor():
		_stand_settle_s = 0.0
		_stand_time_s = 0.0
		_stand_has_ref = false
		_stand_drift_m = 0.0
		_stand_max_drift_m = 0.0
		_stand_reported = false
		return
	_stand_settle_s += delta
	if _stand_settle_s < STAND_SETTLE_S:
		return
	var fixed: LkPosition64 = _fixed_position()
	if not _stand_has_ref:
		_stand_ref = fixed
		_stand_has_ref = true
		return
	_stand_time_s += delta
	_stand_drift_m = fixed.minus(_stand_ref).length()
	_stand_max_drift_m = maxf(_stand_max_drift_m, _stand_drift_m)
	if _stand_time_s >= STAND_GATE_S and not _stand_reported:
		_stand_reported = true
		var verdict: String = "PASS" if _stand_max_drift_m <= STAND_TOLERANCE_M else "FAIL"
		print("RotatingStand: %s stand=%.0f s max_drift=%.2f mm tolerance=%.0f mm surface_speed=%.2f m/s" % [verdict, _stand_time_s, _stand_max_drift_m * 1000.0, STAND_TOLERANCE_M * 1000.0, _surface_speed()])


func _surface_speed() -> float:
	var rel: LkPosition64 = _rotation.relative_position(_frame.get_origin(), _player.global_position)
	return _rotation.surface_velocity(rel).length()


func _process(delta: float) -> void:
	_update_stand_gate(delta)
	var absolute: LkPosition64 = _player.get_absolute_position()
	var center_offset: LkPosition64 = absolute.minus(_center)
	var up_error_deg: float = rad_to_deg(_player.global_basis.y.angle_to(center_offset.direction()))
	_label.text = "Dominant: %s | |g| %.3f m/s2\nOn floor: %s | rel speed %.2f m/s\nAltitude: %.3f m | up vs radial %.3f deg\nSpin %.3f rad/s | angle %.1f deg | surface speed here %.2f m/s\nStand: %.1f / %.0f s | drift %.2f mm | max %.2f mm (tol %.0f mm)\nShifts: %d | local %s" % [
		_player.dominant_body_id,
		_player.gravity_acceleration.length(),
		_player.is_on_floor(),
		_player.velocity.length(),
		center_offset.length() - PLANET_RADIUS_M,
		up_error_deg,
		PLANET_ROTATION_RAD_S,
		rad_to_deg(_rotation.angle_rad),
		_surface_speed(),
		_stand_time_s,
		STAND_GATE_S,
		_stand_drift_m * 1000.0,
		_stand_max_drift_m * 1000.0,
		STAND_TOLERANCE_M * 1000.0,
		_shifts,
		_player.global_position,
	]
