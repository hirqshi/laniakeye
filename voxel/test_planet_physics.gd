extends Node3D

@export var planet_radius_m: float = 6_371_000.0
@export var terrain_height_m: float = 4_000.0
@export var noise_seed: int = 0
@export var gravity_m_s2: float = 9.81

class LocalGenerator:
	extends VoxelGeneratorScript
	var surface: PlanetVoxelGenerator
	var origin_y: float = 0.0

	func _get_used_channels_mask() -> int:
		return 1 << VoxelBuffer.CHANNEL_SDF

	func _generate_block(buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
		var size: Vector3i = buffer.get_size()
		var stride: float = float(1 << lod)
		for x: int in range(size.x):
			var dx: float = float(origin.x) + float(x) * stride
			for y: int in range(size.y):
				var dy: float = origin_y + float(origin.y) + float(y) * stride
				for z: int in range(size.z):
					var dz: float = float(origin.z) + float(z) * stride
					var radial: float = sqrt(dx * dx + dy * dy + dz * dz)
					var direction: Vector3 = Vector3(dx / radial, dy / radial, dz / radial)
					var sdf: float = (radial - surface._get_surface_radius(direction)) / stride
					buffer.set_voxel_f(clampf(sdf, -4.0, 4.0), x, y, z, VoxelBuffer.CHANNEL_SDF)

var _terrain: VoxelLodTerrain
var _body: CharacterBody3D
var _camera: Camera3D
var _head: Node3D
var _capsule: CapsuleShape3D
var _label: Label
var _logical_origin_y: float = 0.0
var _pitch: float = 0.0
var _waiting: bool = true
var _flying: bool = false
var _stable_ticks: int = 0
var _wait_s: float = 0.0
var _hud_s: float = 0.0
var _warned: bool = false
var _status: String = "WAITING FOR COLLISION"


func _ready() -> void:
	var surface: PlanetVoxelGenerator = PlanetVoxelGenerator.new()
	surface.planet_radius_m = planet_radius_m
	surface.terrain_height_m = terrain_height_m
	surface.noise_seed = noise_seed
	surface._noise.seed = noise_seed
	_logical_origin_y = surface._get_surface_radius(Vector3.UP)
	var generator: LocalGenerator = LocalGenerator.new()
	generator.surface = surface
	generator.origin_y = _logical_origin_y
	_terrain = VoxelLodTerrain.new()
	_terrain.name = "LocalTerrain"
	_terrain.generator = generator
	_terrain.mesher = VoxelMesherTransvoxel.new()
	_terrain.lod_count = 5
	_terrain.lod_distance = 64.0
	_terrain.mesh_block_size = 16
	_terrain.view_distance = 192
	_terrain.voxel_bounds = AABB(Vector3(-256.0, -256.0, -256.0), Vector3(512.0, 512.0, 512.0))
	_terrain.generate_collisions = true
	_terrain.collision_lod_count = 2
	_terrain.collision_layer = 1
	_terrain.collision_mask = 1
	_terrain.collision_update_delay = 0
	_terrain.threaded_update_enabled = false
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.45, 0.3)
	material.roughness = 1.0
	_terrain.material = material
	add_child(_terrain)
	_body = CharacterBody3D.new()
	_body.name = "PhysicsProbe"
	_body.position = Vector3(0.0, 3.0, 0.0)
	_body.collision_layer = 2
	_body.collision_mask = 1
	_body.safe_margin = 0.01
	_body.floor_snap_length = 0.25
	_body.floor_max_angle = deg_to_rad(55.0)
	_body.floor_constant_speed = true
	_body.floor_stop_on_slope = true
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.35
	_capsule.height = 1.8
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = _capsule
	_body.add_child(collision)
	_head = Node3D.new()
	_head.position.y = 0.65
	_body.add_child(_head)
	_camera = Camera3D.new()
	_camera.near = 0.1
	_camera.far = 1200.0
	_camera.current = true
	_head.add_child(_camera)
	var viewer: VoxelViewer = VoxelViewer.new()
	viewer.view_distance = 192
	viewer.requires_visuals = true
	viewer.requires_collisions = true
	_body.add_child(viewer)
	add_child(_body)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.12, 0.2)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.65, 0.75)
	environment.ambient_light_energy = 0.4
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 0.8
	add_child(sun)
	var canvas: CanvasLayer = CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(12.0, 12.0)
	_label.add_theme_font_size_override("font_size", 14)
	canvas.add_child(_label)
	add_child(canvas)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("VoxelPhysics: waiting for actual terrain collision; local origin y=", _logical_origin_y)


func _up_at(point: Vector3) -> Vector3:
	var dx: float = point.x
	var dy: float = _logical_origin_y + float(point.y)
	var dz: float = point.z
	var radial: float = sqrt(dx * dx + dy * dy + dz * dz)
	return Vector3(dx / radial, dy / radial, dz / radial)


func _begin_spawn() -> void:
	_body.position = Vector3(0.0, 3.0, 0.0)
	_body.velocity = Vector3.ZERO
	_body.basis = Basis.IDENTITY
	_waiting = true
	_flying = false
	_stable_ticks = 0
	_wait_s = 0.0
	_warned = false
	_status = "WAITING FOR COLLISION"


func _try_spawn(delta: float) -> void:
	_wait_s += delta
	_body.velocity = Vector3.ZERO
	var area: AABB = AABB(Vector3(-4.0, -8.0, -4.0), Vector3(8.0, 16.0, 8.0))
	if not _terrain.is_area_meshed(area, 0):
		_stable_ticks = 0
		return
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(0.0, 16.0, 0.0), Vector3(0.0, -16.0, 0.0), 1, [_body.get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		_stable_ticks = 0
		return
	var hit_position: Vector3 = hit["position"]
	var target: Vector3 = hit_position + _up_at(hit_position) * 1.4
	var shape_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	shape_query.shape = _capsule
	shape_query.transform = Transform3D(Basis.IDENTITY, target)
	shape_query.collision_mask = 1
	shape_query.exclude = [_body.get_rid()]
	shape_query.margin = 0.05
	if not get_world_3d().direct_space_state.intersect_shape(shape_query, 1).is_empty():
		_stable_ticks = 0
		return
	_stable_ticks += 1
	if _stable_ticks >= 5:
		_body.position = target
		_waiting = false
		_status = "WALK"
		print("VoxelPhysics: collision ready; released capsule at ", target)


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	if _waiting:
		_try_spawn(delta)
		if _wait_s > 30.0 and not _warned:
			_warned = true
			push_warning("VoxelPhysics: collision not ready after 30 s; player remains frozen")
	elif _flying:
		var axes: Vector3 = Vector3(Input.get_axis("move_left", "move_right"), Input.get_axis("move_down", "move_up"), Input.get_axis("move_forward", "move_back"))
		_body.position += (_camera.global_basis * axes).limit_length() * 20.0 * delta
		_body.velocity = Vector3.ZERO
		_status = "FLY / NO COLLISIONS; F8 returns to safe spawn"
		if _body.position.length() > 220.0:
			_begin_spawn()
	else:
		_walk(delta)
	_hud_s -= delta
	if _hud_s <= 0.0:
		_hud_s = 0.2
		_label.text = "LOCAL VOXEL PHYSICS (128 m test radius)\n%s | floor=%s | speed=%.2f m/s\npos=%s\ndata=%d meshes=%d wait=%.1fs\nWASD move | Shift run | Space jump\nF8 fly / safe respawn | R respawn | Esc mouse" % [_status, _body.is_on_floor(), _body.velocity.length(), _body.position, _terrain.debug_get_data_block_count(), _terrain.debug_get_mesh_block_count(), _wait_s]


func _walk(delta: float) -> void:
	var area: AABB = AABB(_body.position - Vector3(4.0, 8.0, 4.0), Vector3(8.0, 16.0, 8.0))
	if not _terrain.is_area_meshed(area, 0):
		_body.velocity = Vector3.ZERO
		_status = "WAITING FOR LOCAL MESH"
		return
	var up: Vector3 = _up_at(_body.position)
	_body.up_direction = up
	var forward: Vector3 = -_body.basis.z
	forward = (forward - up * forward.dot(up)).normalized()
	var right: Vector3 = forward.cross(up).normalized()
	_body.basis = Basis(right, up, -forward).orthonormalized()
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (_body.basis * Vector3(input.x, 0.0, input.y)).limit_length()
	var horizontal_position: Vector3 = Vector3(_body.position.x, 0.0, _body.position.z)
	if horizontal_position.length() > 128.0 and direction.dot(horizontal_position) > 0.0:
		direction = Vector3.ZERO
		_status = "TEST EDGE: turn back"
	else:
		_status = "WALK"
	var speed: float = 7.0 if Input.is_action_pressed("run") else 4.0
	var vertical: float = _body.velocity.dot(up)
	if _body.is_on_floor() and vertical < 0.0:
		vertical = 0.0
	if _body.is_on_floor() and Input.is_action_just_pressed("jump"):
		vertical = 5.0
	vertical -= gravity_m_s2 * delta
	_body.velocity = direction * speed + up * vertical
	_body.move_and_slide()
	if _body.position.y < -64.0:
		push_warning("VoxelPhysics: fell below test patch; respawning, inspect collisions")
		_begin_spawn()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_body.rotate_object_local(Vector3.UP, -event.relative.x * 0.002)
		_pitch = clampf(_pitch - event.relative.y * 0.002, -1.5, 1.5)
		_head.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F8:
			if _flying:
				_begin_spawn()
			else:
				_flying = true
				_waiting = false
				_body.velocity = Vector3.ZERO
		elif event.keycode == KEY_R:
			_begin_spawn()
		elif event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
