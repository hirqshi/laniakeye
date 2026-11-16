extends Node3D

const PLANET_RADIUS_M: float = 200.0
const SURFACE_G: float = 9.8
const SHIFT_THRESHOLD_M: float = 64.0

var _frame: LkCoordinateFrame
var _gravity: LkGravityService
var _player: LkPlayerController
var _label: Label
var _shifts: int = 0
var _start_absolute: LkPosition64


func _ready() -> void:
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
	var center: LkPosition64 = LkPosition64.new(149597870700.0, 0.0, 0.0)
	var spawn_distance: float = PLANET_RADIUS_M + 2.0
	_start_absolute = LkPosition64.new(center.x + dir.x * spawn_distance, center.y + dir.y * spawn_distance, center.z + dir.z * spawn_distance)

	_frame = LkCoordinateFrame.new()
	_frame.threshold_m = SHIFT_THRESHOLD_M
	_frame.initialize_origin(_start_absolute)
	_frame.shifted.connect(func(_delta: Vector3) -> void: _shifts += 1)

	_gravity = LkGravityService.new()
	_gravity.bodies.append(LkGravityBody.new(&"test_planet", center, PLANET_RADIUS_M, SURFACE_G * PLANET_RADIUS_M * PLANET_RADIUS_M))

	var planet: StaticBody3D = StaticBody3D.new()
	planet.name = "TestPlanet"
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = PLANET_RADIUS_M
	shape.shape = sphere_shape
	planet.add_child(shape)
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
	planet.add_child(mesh)
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
		planet.add_child(marker)
	planet.position = _frame.to_local(center)
	add_child(planet)

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
	_frame.register_root(planet)

	var canvas: CanvasLayer = CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	canvas.add_child(_label)
	add_child(canvas)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("LkPlayerTest: WASD, mouse look, Space jump, Shift run, Esc releases mouse")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	var absolute: LkPosition64 = _player.get_absolute_position()
	var center_offset: LkPosition64 = absolute.minus(LkPosition64.new(149597870700.0, 0.0, 0.0))
	var up_error_deg: float = rad_to_deg(_player.global_basis.y.angle_to(center_offset.direction()))
	_label.text = "Dominant: %s | |g| %.3f m/s2\nOn floor: %s | speed %.2f m/s\nAltitude: %.3f m\nUp vs radial: %.3f deg\nShifts: %d | local %s" % [
		_player.dominant_body_id,
		_player.gravity_acceleration.length(),
		_player.is_on_floor(),
		_player.velocity.length(),
		center_offset.length() - PLANET_RADIUS_M,
		up_error_deg,
		_shifts,
		_player.global_position,
	]
