extends Node3D

# Isolated voxel origin-shift gate.
# Terrain remains a LOCAL Node3D and is rebased with the scene. Voxel edit
# addresses are recorded in ABSOLUTE coordinates through LkVoxelOriginAdapter.
# This does not integrate with the main game scene or persist edits to disk.

const PLANET_RADIUS_M: float = 6371000.0
const SHIFT_THRESHOLD_M: float = 48.0
const MOVE_SPEED_MPS: float = 6.0
const RETURN_DISTANCE_M: float = 40.0
const DIG_RADIUS_M: float = 1.5
const DIG_STRENGTH: float = 0.5


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
var _dig_target_absolute: LkPosition64
var _dig_recorded: bool = false
var _returning: bool = false
var _shifts: int = 0
var _waiting_for_mesh: bool = true
var _wait_time: float = 0.0
var _elapsed: float = 0.0
var _result: String = "DIG A HOLE WITH LMB"

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
		push_error("VoxelOriginShiftTest: failed to initialize coordinate frame")
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
	# VoxelLodTerrain generates blocks around active VoxelViewer nodes.
	# Without a viewer requesting visuals and collisions, is_area_meshed()
	# never becomes true.
	var viewer: VoxelViewer = VoxelViewer.new()
	viewer.view_distance = 96
	viewer.requires_visuals = true
	viewer.requires_collisions = true
	camera_pivot.add_child(viewer)
	add_child(_body)
	if not (_frame.register_root(_body) and _frame.register_root(_terrain)):
		push_error("VoxelOriginShiftTest: failed to register roots")
		set_physics_process(false)
		return
	_absolute = _frame.to_absolute(_body.global_position)
	var canvas: CanvasLayer = CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_font_size_override("font_size", 15)
	canvas.add_child(_label)
	add_child(canvas)
	print("VoxelOriginShiftTest: dig a hole, then walk forward to trigger rebases")

func _physics_process(delta: float) -> void:
	if _waiting_for_mesh:
		_wait_time += delta
		var area: AABB = AABB(Vector3(-32.0, -16.0, -32.0), Vector3(64.0, 32.0, 64.0))
		if _terrain.is_area_meshed(area, 0):
			_waiting_for_mesh = false
			_result = "DIG A HOLE WITH LMB"
		elif _wait_time > 20.0:
			_result = "TIMEOUT WAITING FOR MESH"
			push_error("VoxelOriginShiftTest: terrain mesh did not become ready")
			set_physics_process(false)
		_update_hud()
		return
	_elapsed += delta
	if _returning:
		_return_to_hole(delta)
	else:
		_walk_and_dig(delta)
	if _frame.maybe_shift(_body.global_position):
		_shifts += 1
		_result = "REBASED; RETURNING TO HOLE" if _returning else "REBASED; KEEP DIGGING OR WALK FORWARD"
		print("VoxelOriginShiftTest: rebase #", _shifts, " origin=", _frame.get_origin().x, ",", _frame.get_origin().y, ",", _frame.get_origin().z)
	_absolute = _frame.to_absolute(_body.global_position)
	_update_hud()

func _walk_and_dig(delta: float) -> void:
	_body.velocity = Vector3(MOVE_SPEED_MPS, 0.0, 0.0)
	_body.move_and_slide()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var camera_origin: Vector3 = _camera.global_position
		var direction: Vector3 = -_camera.global_basis.z.normalized()
		var hit: VoxelRaycastResult = _tool.raycast(camera_origin, direction, 8.0)
		if hit != null:
			var surface_local: Vector3 = camera_origin + direction * hit.distance
			var surface_absolute: LkPosition64 = _frame.to_absolute(_terrain.to_global(surface_local))
			var center_absolute: LkPosition64 = surface_absolute.plus(LkPosition64.new(0.0, -DIG_RADIUS_M * 0.25, 0.0))
			var voxel_center: Vector3i = _adapter.absolute_to_voxel(center_absolute)
			var terrain_center: Vector3 = Vector3(voxel_center) + Vector3(0.5, 0.5, 0.5)
			_tool.mode = VoxelTool.MODE_REMOVE
			_tool.grow_sphere(terrain_center, DIG_RADIUS_M, DIG_STRENGTH)
			if not _dig_recorded:
				_dig_recorded = true
				_dig_target_absolute = center_absolute
				_adapter.record_edit(center_absolute, DIG_RADIUS_M, true)
				_result = "HOLE RECORDED IN ABSOLUTE COORDINATES"
			else:
				_result = "DIGGING"
	if _dig_recorded and _absolute.minus(_dig_target_absolute).length() >= RETURN_DISTANCE_M:
		_returning = true
		_result = "WALKING BACK TO ABSOLUTE HOLE LOCATION"

func _return_to_hole(delta: float) -> void:
	var target_local: Vector3 = _frame.to_local(_dig_target_absolute)
	var direction: Vector3 = target_local - _body.global_position
	direction.y = 0.0
	if direction.length() < 1.0:
		_body.velocity = Vector3.ZERO
		var near_hole: bool = _adapter.has_edit_near(_dig_target_absolute, 3.0)
		_result = "PASS: HOLE REMAINED AT ABSOLUTE LOCATION" if near_hole else "FAIL: EDIT RECORD NOT FOUND NEAR TARGET"
		print("VoxelOriginShiftTest: ", _result, " shifts=", _shifts, " edits=", _adapter.edit_count())
		set_physics_process(false)
		return
	_body.velocity = direction.normalized() * MOVE_SPEED_MPS
	_body.move_and_slide()
	_result = "RETURNING: %.1f m TO ABSOLUTE HOLE" % direction.length()

func _update_hud() -> void:
	_label.text = "Voxel origin-shift gate\n%s\nShifts: %d | threshold %.0f m\nEdits: %d | dig recorded: %s\nAbsolute position: %.3f, %.3f, %.3f m\nLocal position: %s\n\nLMB: dig | Walk +X to trigger rebase\nAfter rebase, walk back: the hole must remain in place.\nScope: local voxel terrain only; no persistence, main scene, or planet rotation." % [
		_result,
		_shifts,
		SHIFT_THRESHOLD_M,
		_adapter.edit_count(),
		"YES" if _dig_recorded else "NO",
		_absolute.x,
		_absolute.y,
		_absolute.z,
		_body.global_position
	]
