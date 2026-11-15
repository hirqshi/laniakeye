extends Node3D

# Isolated voxel chunk-boundary origin-shift gate.
# The brush is deliberately centered on the X=0 and Z=0 chunk boundaries.
# A dig/build must update both adjacent chunks, survive origin shifts, and
# retain its absolute voxel address. No disk persistence or main-game wiring.

const PLANET_RADIUS_M: float = 6371000.0
const SHIFT_THRESHOLD_M: float = 48.0
const WALK_SPEED_MPS: float = 4.0
const RUN_SPEED_MPS: float = 7.0
const JUMP_SPEED_MPS: float = 5.0
const GRAVITY_MPS2: float = 9.81
const REQUIRED_SHIFTS: int = 2
const DIG_RADIUS_M: float = 2.0
const BUILD_RADIUS_M: float = 1.5
const EDIT_STRENGTH: float = 0.5


class FlatGenerator:
	extends VoxelGeneratorScript

	func _get_used_channels_mask() -> int:
		return 1 << VoxelBuffer.CHANNEL_SDF

	func _generate_block(buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
		var size: Vector3i = buffer.get_size()
		var stride: float = float(1 << lod)
		for x: int in range(size.x):
			for y: int in range(size.y):
				var world_y: float = float(origin.y) + float(y) * stride
				var sdf: float = clampf(world_y / stride, -4.0, 4.0)
				for z: int in range(size.z):
					buffer.set_voxel_f(sdf, x, y, z, VoxelBuffer.CHANNEL_SDF)


var _frame: LkCoordinateFrame
var _adapter: LkVoxelOriginAdapter
var _terrain: VoxelLodTerrain
var _body: CharacterBody3D
var _camera: Camera3D
var _tool: VoxelToolLodTerrain
var _label: Label
var _absolute: LkPosition64
var _boundary_edit: Dictionary = {}
var _returning: bool = false
var _shifts: int = 0
var _waiting_for_mesh: bool = true
var _wait_time: float = 0.0
var _pitch: float = 0.0
var _result: String = "STAND ON X=0 / Z=0 AND DIG WITH LMB"

func _ready() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.11, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.7, 0.8)
	environment.ambient_light_energy = 0.45
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	add_child(sun)
	_frame = LkCoordinateFrame.new()
	_frame.threshold_m = SHIFT_THRESHOLD_M
	var surface_absolute: LkPosition64 = LkPosition64.new(149597870700.0, PLANET_RADIUS_M, 0.0)
	if not _frame.initialize_origin(surface_absolute):
		push_error("VoxelChunkBoundaryTest: failed to initialize coordinate frame")
		set_physics_process(false)
		return
	_terrain = VoxelLodTerrain.new()
	_terrain.name = "LocalTerrain"
	_terrain.generator = FlatGenerator.new()
	_terrain.mesher = VoxelMesherTransvoxel.new()
	_terrain.mesh_block_size = 16
	_terrain.view_distance = 96
	_terrain.lod_count = 1
	_terrain.generate_collisions = true
	_terrain.collision_layer = 1
	_terrain.collision_mask = 1
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.38, 0.48, 0.32)
	_terrain.material = material
	add_child(_terrain)
	_adapter = LkVoxelOriginAdapter.new(_frame, _terrain, surface_absolute)
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_SDF
	_tool.sdf_scale = 1.0
	_tool.sdf_strength = 1.0
	_body = CharacterBody3D.new()
	_body.name = "PhysicsProbe"
	_body.position = Vector3(0.0, 3.0, 0.0)
	_body.collision_layer = 2
	_body.collision_mask = 1
	_body.floor_max_angle = deg_to_rad(55.0)
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	_body.add_child(collision)
	var camera_pivot: Node3D = Node3D.new()
	camera_pivot.position.y = 0.65
	_body.add_child(camera_pivot)
	_camera = Camera3D.new()
	_camera.near = 0.1
	_camera.far = 500.0
	_camera.current = true
	camera_pivot.add_child(_camera)
	var viewer: VoxelViewer = VoxelViewer.new()
	viewer.view_distance = 96
	viewer.requires_visuals = true
	viewer.requires_collisions = true
	camera_pivot.add_child(viewer)
	add_child(_body)
	if not (_frame.register_root(_body) and _frame.register_root(_terrain)):
		push_error("VoxelChunkBoundaryTest: failed to register roots")
		set_physics_process(false)
		return
	_absolute = _frame.to_absolute(_body.global_position)
	var canvas: CanvasLayer = CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_font_size_override("font_size", 15)
	canvas.add_child(_label)
	add_child(canvas)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("VoxelChunkBoundaryTest: dig/build exactly at X=0 and Z=0, then trigger 2 rebases")

func _physics_process(delta: float) -> void:
	if _waiting_for_mesh:
		_wait_time += delta
		var area: AABB = AABB(Vector3(-32.0, -16.0, -32.0), Vector3(64.0, 32.0, 64.0))
		if _terrain.is_area_meshed(area, 0):
			_waiting_for_mesh = false
			_result = "STAND ON X=0 / Z=0 AND DIG WITH LMB"
		elif _wait_time > 20.0:
			_result = "TIMEOUT WAITING FOR MESH"
			push_error("VoxelChunkBoundaryTest: terrain mesh did not become ready")
			set_physics_process(false)
		_update_hud()
		return
	if _returning:
		_return_to_boundary(delta)
	else:
		_move_and_edit(delta)
	if _frame.maybe_shift(_body.global_position):
		_shifts += 1
		_result = "REBASED; %s" % ("RETURN TO BOUNDARY EDIT" if _returning else "TRAVEL 48 m FOR ANOTHER REBASE")
		print("VoxelChunkBoundaryTest: rebase #", _shifts, " origin=", _frame.get_origin().x, ",", _frame.get_origin().y, ",", _frame.get_origin().z)
	_absolute = _frame.to_absolute(_body.global_position)
	_update_hud()

func _move_and_edit(delta: float) -> void:
	_move(delta)
	var digging: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var building: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if digging and building:
		_result = "USE ONE MOUSE BUTTON AT A TIME"
		return
	if not digging and not building:
		return
	var camera_origin: Vector3 = _camera.global_position
	var look: Vector3 = -_camera.global_basis.z.normalized()
	var hit: VoxelRaycastResult = _tool.raycast(camera_origin, look, 8.0)
	if hit == null:
		return
	var surface_local: Vector3 = camera_origin + look * hit.distance
	var surface_absolute: LkPosition64 = _frame.to_absolute(_terrain.to_global(surface_local))
	var radius: float = DIG_RADIUS_M if digging else BUILD_RADIUS_M
	# Force the edit center onto both chunk boundaries. With 16-voxel blocks,
	# X=0 and Z=0 are boundaries between negative and positive chunk columns.
	var boundary_absolute: LkPosition64 = LkPosition64.new(0.0, surface_absolute.y - radius * 0.25, 0.0)
	var voxel_center: Vector3i = _adapter.absolute_to_voxel(boundary_absolute)
	var terrain_center: Vector3 = Vector3(voxel_center) + Vector3(0.5, 0.5, 0.5)
	_tool.mode = VoxelTool.MODE_REMOVE if digging else VoxelTool.MODE_ADD
	_tool.grow_sphere(terrain_center, radius, EDIT_STRENGTH)
	if _boundary_edit.is_empty():
		_boundary_edit = {
			"absolute": boundary_absolute.copy(),
			"voxel": voxel_center,
			"radius": radius,
			"remove": digging
		}
		_adapter.record_edit(boundary_absolute, radius, digging)
		_result = "BOUNDARY EDIT RECORDED AT X=0 / Z=0"
		print("VoxelChunkBoundaryTest: recorded boundary edit ", _boundary_edit)
	else:
		_result = "EDITING CHUNK BOUNDARY"
	if not _boundary_edit.is_empty() and _shifts >= REQUIRED_SHIFTS:
		_returning = true
		_result = "RETURN TO THE BOUNDARY EDIT"

func _return_to_boundary(delta: float) -> void:
	var target: LkPosition64 = _boundary_edit["absolute"]
	var target_local: Vector3 = _frame.to_local(target)
	var direction: Vector3 = target_local - _body.global_position
	direction.y = 0.0
	if direction.length() < 1.0:
		_body.velocity = Vector3.ZERO
		var found: bool = _adapter.has_edit_near(target, 3.0)
		_result = "PASS: BOUNDARY EDIT REMAINED AT ABSOLUTE LOCATION" if found else "FAIL: BOUNDARY EDIT NOT FOUND"
		print("VoxelChunkBoundaryTest: ", _result, " shifts=", _shifts)
		set_physics_process(false)
		return
	_move(delta)
	_result = "RETURNING: %.1f m TO BOUNDARY EDIT" % direction.length()

func _move(delta: float) -> void:
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (_body.global_basis * Vector3(input.x, 0.0, input.y)).limit_length()
	var speed: float = RUN_SPEED_MPS if Input.is_action_pressed("run") else WALK_SPEED_MPS
	var vertical: float = _body.velocity.y
	if _body.is_on_floor() and vertical < 0.0:
		vertical = 0.0
	if _body.is_on_floor() and Input.is_action_just_pressed("jump"):
		vertical = JUMP_SPEED_MPS
	vertical -= GRAVITY_MPS2 * delta
	_body.velocity = direction * speed + Vector3.UP * vertical
	_body.move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_body.rotate_object_local(Vector3.UP, -event.relative.x * 0.002)
		_pitch = clampf(_pitch - event.relative.y * 0.002, -1.5, 1.5)
		_camera.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _update_hud() -> void:
	_label.text = "Voxel chunk-boundary origin-shift gate\n%s\nShifts: %d / %d\nBoundary edit recorded: %s\nAbsolute position: %.3f, %.3f, %.3f m\nLocal position: %s\n\nWASD move | Shift run | Space jump\nLMB dig | RMB build | Mouse look | Esc mouse\nStand near X=0 / Z=0, edit the ground, travel 48 m twice, then return." % [
		_result,
		_shifts,
		REQUIRED_SHIFTS,
		"YES" if not _boundary_edit.is_empty() else "NO",
		_absolute.x,
		_absolute.y,
		_absolute.z,
		_body.global_position
	]
