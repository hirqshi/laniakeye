extends Node3D

# Gate 1: anchored voxel patch on a ROTATING Earth-size planet.
# Static anchor, no edits, no re-anchoring. Terrain-local u = planet-fixed q - A,
# lattice axes = planet-fixed axes. Terrain node transform is recomputed from
# doubles every tick: basis = R(theta), origin = R(theta)*A + (center - origin).

const PLANET_RADIUS_M: float = 6371000.0
const TERRAIN_HEIGHT_M: float = 4000.0
const NOISE_SEED: int = 0
const SURFACE_G: float = 9.81
const SHIFT_THRESHOLD_M: float = 64.0
const SLOW_SURFACE_SPEED_MPS: float = 4.0
const EARTH_OMEGA_RAD_S: float = 7.2921e-5
const SPAWN_DIRECTION: Vector3 = Vector3(0.7071, 0.7071, 0.0)
const SPIN_AXIS: Vector3 = Vector3(0.3, 0.9, 0.1)
const RESPAWN_DISTANCE_M: float = 230.0
const CARRY_LIMIT_M: float = PLANET_RADIUS_M + TERRAIN_HEIGHT_M + 500.0
const STAND_SETTLE_S: float = 2.0
const STAND_TOLERANCE_M: float = 0.02
const DAY_30_MIN_OMEGA_RAD_S: float = TAU / 1800.0
const STAND_REPORT_TIMES_S: Array[float] = [30.0, 120.0, 300.0]


class AnchoredGenerator:
	extends VoxelGeneratorScript
	var surface: PlanetVoxelGenerator
	var anchor: LkPosition64

	func _get_used_channels_mask() -> int:
		return 1 << VoxelBuffer.CHANNEL_SDF

	func _generate_block(buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
		var size: Vector3i = buffer.get_size()
		var stride: float = float(1 << lod)
		for x: int in range(size.x):
			var qx: float = anchor.x + float(origin.x) + float(x) * stride
			for y: int in range(size.y):
				var qy: float = anchor.y + float(origin.y) + float(y) * stride
				for z: int in range(size.z):
					var qz: float = anchor.z + float(origin.z) + float(z) * stride
					var radial: float = sqrt(qx * qx + qy * qy + qz * qz)
					var direction: Vector3 = Vector3(qx / radial, qy / radial, qz / radial)
					var sdf: float = (radial - surface._get_surface_radius(direction)) / stride
					buffer.set_voxel_f(clampf(sdf, -4.0, 4.0), x, y, z, VoxelBuffer.CHANNEL_SDF)


var _frame: LkCoordinateFrame
var _gravity: LkGravityService
var _rotation: LkRotatingFrame
var _surface: PlanetVoxelGenerator
var _terrain: VoxelLodTerrain
var _player: LkPlayerController
var _capsule: CapsuleShape3D
var _label: Label

var _center: LkPosition64
var _q0: LkPosition64
var _anchor: LkPosition64
var _u0: Vector3
var _spawn_dir: Vector3
var _slow_omega: float = 0.0
var _shifts: int = 0

var _waiting: bool = true
var _stable_ticks: int = 0
var _wait_s: float = 0.0
var _status: String = "WAITING FOR MESH + COLLISION"

var _stand_settle_s: float = 0.0
var _stand_time_s: float = 0.0
var _stand_has_ref: bool = false
var _stand_ref: LkPosition64
var _stand_drift_m: float = 0.0
var _stand_max_drift_m: float = 0.0

var _spin_mode: int = 0
var _stand_reports: int = 0
var _voxel_tool: VoxelToolLodTerrain
var _mismatch_log_s: float = 0.0
var _stand_map_ref: Vector3 = Vector3.ZERO


func _ready() -> void:
	process_physics_priority = -100

	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.05, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.4
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	add_child(sun)

	_surface = PlanetVoxelGenerator.new()
	_surface.planet_radius_m = PLANET_RADIUS_M
	_surface.terrain_height_m = TERRAIN_HEIGHT_M
	_surface.noise_seed = NOISE_SEED
	_surface._noise.seed = NOISE_SEED
	
	_spawn_dir = SPAWN_DIRECTION.normalized()
	var surface_radius: float = _surface._get_surface_radius(_spawn_dir)
	_q0 = LkPosition64.new(_spawn_dir.x * (surface_radius + 3.0), _spawn_dir.y * (surface_radius + 3.0), _spawn_dir.z * (surface_radius + 3.0))
	_anchor = LkPosition64.new(floorf(_q0.x), floorf(_q0.y), floorf(_q0.z))
	_u0 = Vector3(_q0.x - _anchor.x, _q0.y - _anchor.y, _q0.z - _anchor.z)
	print("VoxelRotatingGate: anchor=%s u0=%s |u0|=%.4f m" % [_anchor.x, _u0, _u0.length()])
	_center = LkPosition64.new(149597870700.0, 0.0, 0.0)

	_frame = LkCoordinateFrame.new()
	_frame.threshold_m = SHIFT_THRESHOLD_M
	_frame.initialize_origin(_center.plus(_q0))
	_frame.shifted.connect(func(_delta: Vector3) -> void:
		_shifts += 1
		_update_terrain_transform()
	)

	_gravity = LkGravityService.new()
	_gravity.bodies.append(LkGravityBody.new(&"test_planet", _center, surface_radius, SURFACE_G * surface_radius * surface_radius))

	var lever: float = surface_radius * SPIN_AXIS.normalized().cross(_spawn_dir).length()
	_slow_omega = SLOW_SURFACE_SPEED_MPS / lever
	_rotation = LkRotatingFrame.new(&"test_planet", _center, SPIN_AXIS, _slow_omega)

	var generator: AnchoredGenerator = AnchoredGenerator.new()
	generator.surface = _surface
	generator.anchor = _anchor
	_terrain = VoxelLodTerrain.new()
	_terrain.name = "AnchoredTerrain"
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
	_voxel_tool = _terrain.get_voxel_tool()
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	_voxel_tool.set_raycast_binary_search_iterations(8)
	_add_pillars()

	_player = LkPlayerController.new()
	_player.name = "Player"
	_player.collision_layer = 2
	_player.collision_mask = 1
	_player.safe_margin = 0.01
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.35
	_capsule.height = 1.8
	var player_shape: CollisionShape3D = CollisionShape3D.new()
	player_shape.shape = _capsule
	_player.add_child(player_shape)
	var pivot: Node3D = Node3D.new()
	pivot.position.y = 0.65
	_player.add_child(pivot)
	var camera: Camera3D = Camera3D.new()
	camera.near = 0.05
	camera.far = 2000.0
	pivot.add_child(camera)
	var viewer: VoxelViewer = VoxelViewer.new()
	viewer.view_distance = 192
	viewer.requires_visuals = true
	viewer.requires_collisions = true
	_player.add_child(viewer)
	_player.camera_pivot = pivot
	_player.player_camera = camera
	_player.setup(_frame, _gravity)
	add_child(_player)

	var canvas: CanvasLayer = CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	canvas.add_child(_label)
	add_child(canvas)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_terrain_transform()
	_begin_spawn()
	print("VoxelRotatingGate: waiting for mesh + collision. T toggles slow/Earth spin, R respawns, Esc mouse")


func _add_pillars() -> void:
	var t1: Vector3 = _spawn_dir.cross(Vector3.FORWARD).normalized()
	var t2: Vector3 = _spawn_dir.cross(t1).normalized()
	var pillar_material: StandardMaterial3D = StandardMaterial3D.new()
	pillar_material.albedo_color = Color(0.9, 0.45, 0.15)
	for i: int in range(6):
		var angle: float = float(i) * TAU / 6.0
		var offset: Vector3 = (t1 * cos(angle) + t2 * sin(angle)) * 30.0
		var q: LkPosition64 = LkPosition64.new(_q0.x + offset.x, _q0.y + offset.y, _q0.z + offset.z)
		var direction: Vector3 = q.direction()
		var surface_r: float = _surface._get_surface_radius(direction)
		var pillar: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(2.0, 40.0, 2.0)
		pillar.mesh = box
		pillar.material_override = pillar_material
		var u: Vector3 = Vector3(direction.x * surface_r - _anchor.x, direction.y * surface_r - _anchor.y, direction.z * surface_r - _anchor.z)
		pillar.transform = Transform3D(_basis_for_up(direction), u)
		_terrain.add_child(pillar)


func _basis_for_up(up: Vector3) -> Basis:
	var forward: Vector3 = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	if forward.length_squared() < 0.001:
		forward = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	forward = forward.normalized()
	var right: Vector3 = forward.cross(up).normalized()
	return Basis(right, up, -forward)


func _spawn_up() -> Vector3:
	var rotated: LkPosition64 = _rotation.rotate(LkPosition64.new(_spawn_dir.x, _spawn_dir.y, _spawn_dir.z), _rotation.angle_rad)
	return Vector3(rotated.x, rotated.y, rotated.z).normalized()


func _update_terrain_transform() -> void:
	if _terrain == null or _rotation == null or _frame == null:
		return
	var anchor_now: LkPosition64 = _rotation.rotate(_anchor, _rotation.angle_rad)
	var center_local: LkPosition64 = _center.minus(_frame.get_origin())
	var position_local: LkPosition64 = anchor_now.plus(center_local)
	_terrain.global_transform = Transform3D(_rotation.planet_basis(), Vector3(position_local.x, position_local.y, position_local.z))
	_terrain.force_update_transform()


func _begin_spawn() -> void:
	_waiting = true
	_stable_ticks = 0
	_wait_s = 0.0
	_status = "WAITING FOR MESH + COLLISION"
	_player.set_controllable(false)
	_player.detach_from_frame()
	_player.velocity = Vector3.ZERO
	var spawn_absolute: LkPosition64 = _center.plus(_rotation.rotate(_q0, _rotation.angle_rad))
	_player.global_position = _frame.to_local(spawn_absolute)
	_reset_stand()


func _try_spawn(delta: float) -> void:
	_wait_s += delta
	_update_terrain_transform()
	var area: AABB = AABB(_u0 - Vector3(8.0, 8.0, 8.0), Vector3(16.0, 16.0, 16.0))
	if not _terrain.is_area_meshed(area, 0):
		_stable_ticks = 0
		return
	var up: Vector3 = _spawn_up()
	var from: Vector3 = _player.global_position
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from + up * 16.0, from - up * 16.0, 1, [_player.get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		_stable_ticks = 0
		return
	var hit_position: Vector3 = hit["position"]
	var target: Vector3 = hit_position + up * 1.4
	var placed: Basis = _basis_for_up(up)
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.transform = Transform3D(placed, target)
	query.collision_mask = 1
	query.exclude = [_player.get_rid()]
	query.margin = 0.05
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		_stable_ticks = 0
		return
	_stable_ticks += 1
	if _stable_ticks >= 5:
		_player.global_transform = Transform3D(placed, target)
		_player.velocity = Vector3.ZERO
		_player.set_controllable(true)
		_player.attach_to_frame(_rotation)
		_waiting = false
		_status = "WALK"
		print("VoxelRotatingGate: collision ready after %.1f s; player released at local %s" % [_wait_s, target])


func _physics_process(delta: float) -> void:
	if _waiting:
		_try_spawn(delta)
		return
	var step: float = _rotation.advance(delta)
	_update_terrain_transform()
	_player.carry_with_frame(_rotation, step, CARRY_LIMIT_M)
	if _anchor_distance_m() > RESPAWN_DISTANCE_M:
		print("VoxelRotatingGate: left the %.0f m patch, respawning" % RESPAWN_DISTANCE_M)
		_begin_spawn()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		elif event.keycode == KEY_T:
			_spin_mode = (_spin_mode + 1) % 4
			_rotation.angular_speed_rad_s = _spin_omega()
			_reset_stand()
		elif event.keycode == KEY_R:
			_begin_spawn()


func _fixed_position() -> LkPosition64:
	var rel: LkPosition64 = _rotation.relative_position(_frame.get_origin(), _player.global_position)
	return _rotation.rotate(rel, -_rotation.angle_rad)


func _anchor_distance_m() -> float:
	return _fixed_position().minus(_anchor).length()


func _map_error_mm() -> Vector3:
	var u: Vector3 = _terrain.to_local(_player.global_position)
	var fixed: LkPosition64 = _fixed_position()
	return Vector3(fixed.x - (_anchor.x + u.x), fixed.y - (_anchor.y + u.y), fixed.z - (_anchor.z + u.z)) * 1000.0


func _map_change_components_mm() -> Vector3:
	var change: Vector3 = _map_error_mm() - _stand_map_ref
	var up: Vector3 = _stand_ref.direction()
	var tangent: Vector3 = _rotation.get_axis().cross(up).normalized()
	var side: Vector3 = up.cross(tangent)
	return Vector3(change.dot(tangent), change.dot(up), change.dot(side))


func _terrain_node_error_mm() -> float:
	var rel: LkPosition64 = _rotation.relative_position(_frame.get_origin(), _terrain.global_position)
	return _rotation.rotate(rel, -_rotation.angle_rad).minus(_anchor).length() * 1000.0


func _terrain_basis_error_mm() -> float:
	var probe: Vector3 = Vector3(0.0, 0.0, 100.0)
	var rel: LkPosition64 = _rotation.relative_position(_frame.get_origin(), _terrain.to_global(probe))
	var expected: LkPosition64 = LkPosition64.new(_anchor.x + probe.x, _anchor.y + probe.y, _anchor.z + probe.z)
	return _rotation.rotate(rel, -_rotation.angle_rad).minus(expected).length() * 1000.0


func _terrain_set_error_mm() -> float:
	var anchor_now: LkPosition64 = _rotation.rotate(_anchor, _rotation.angle_rad)
	var center_local: LkPosition64 = _center.minus(_frame.get_origin())
	var expected: LkPosition64 = anchor_now.plus(center_local)
	var actual: Vector3 = _terrain.global_position
	return Vector3(expected.x - actual.x, expected.y - actual.y, expected.z - actual.z).length() * 1000.0


func _ground_mismatch_m() -> float:
	var up: Vector3 = _player.global_basis.y
	var from: Vector3 = _player.global_position + up * 2.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from - up * 6.0, 1, [_player.get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return NAN
	var hit_position: Vector3 = hit["position"]
	return _voxel_tool.get_voxel_f_interpolated(_terrain.to_local(hit_position))


func _drift_components_mm() -> Vector3:
	var delta: LkPosition64 = _fixed_position().minus(_stand_ref)
	var d: Vector3 = Vector3(delta.x, delta.y, delta.z)
	var up: Vector3 = _stand_ref.direction()
	var tangent: Vector3 = _rotation.get_axis().cross(up).normalized()
	var side: Vector3 = up.cross(tangent)
	return Vector3(d.dot(tangent), d.dot(up), d.dot(side)) * 1000.0


func _surface_speed() -> float:
	var rel: LkPosition64 = _rotation.relative_position(_frame.get_origin(), _player.global_position)
	return _rotation.surface_velocity(rel).length()


func _spin_name() -> String:
	return ["SLOW", "EARTH", "DAY30", "STILL"][_spin_mode]


func _spin_omega() -> float:
	match _spin_mode:
		1:
			return EARTH_OMEGA_RAD_S
		2:
			return DAY_30_MIN_OMEGA_RAD_S
		3:
			return 0.0
	return _slow_omega


func _reset_stand() -> void:
	_stand_settle_s = 0.0
	_stand_time_s = 0.0
	_stand_has_ref = false
	_stand_drift_m = 0.0
	_stand_max_drift_m = 0.0
	_stand_reports = 0


func _update_stand_gate(delta: float) -> void:
	var active: bool = (
		Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_back")
		or Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")
		or Input.is_action_pressed("jump")
	)
	if _waiting or active or not _player.is_on_floor():
		_reset_stand()
		return
	_stand_settle_s += delta
	if _stand_settle_s < STAND_SETTLE_S:
		return
	var fixed: LkPosition64 = _fixed_position()
	if not _stand_has_ref:
		_stand_ref = fixed
		_stand_map_ref = _map_error_mm()
		_stand_has_ref = true
		return
	_stand_time_s += delta
	_stand_drift_m = fixed.minus(_stand_ref).length()
	_stand_max_drift_m = maxf(_stand_max_drift_m, _stand_drift_m)
	if _stand_reports < STAND_REPORT_TIMES_S.size() and _stand_time_s >= STAND_REPORT_TIMES_S[_stand_reports]:
		_stand_reports += 1
		var verdict: String = "PASS" if _stand_max_drift_m <= STAND_TOLERANCE_M else "FAIL"
		var components: Vector3 = _drift_components_mm()
		var map_change: Vector3 = _map_change_components_mm()
		print("VoxelRotatingStand: %s mode=%s t=%.0f s max_drift=%.3f mm angle=%.2f deg shifts=%d along=%.2f up=%.2f side=%.2f mm | map_change along=%.2f up=%.2f side=%.2f mm | node_err=%.4f mm basis_err=%.4f mm | set_err=%.4f mm" % [
			verdict,
			_spin_name(),
			_stand_time_s,
			_stand_max_drift_m * 1000.0,
			rad_to_deg(_rotation.angle_rad),
			_shifts,
			components.x,
			components.y,
			components.z,
			map_change.x,
			map_change.y,
			map_change.z,
			_terrain_node_error_mm(),
			_terrain_basis_error_mm(),
			_terrain_set_error_mm(),
		])


func _process(delta: float) -> void:
	_update_stand_gate(delta)
	var u_player: Vector3 = _terrain.to_local(_player.global_position)
	var meshed: bool = _terrain.is_area_meshed(AABB(u_player - Vector3(4.0, 4.0, 4.0), Vector3(8.0, 8.0, 8.0)), 0)
	var absolute: LkPosition64 = _player.get_absolute_position()
	var center_offset: LkPosition64 = absolute.minus(_center)
	var up_error_deg: float = rad_to_deg(_player.global_basis.y.angle_to(center_offset.direction()))
	_label.text = "%s | spin %s (T)\nOn floor: %s | rel speed %.2f m/s | meshed under player: %s\nRadius %.2f m | up vs radial %.3f deg | |g| %.3f\nSurface speed here %.2f m/s | angle %.4f deg\nAnchor distance %.1f m / %.0f m | mesh blocks %d\nStand: %.1f / %.0f s | drift %.2f mm | max %.2f mm (tol %.0f mm)\nShifts: %d | local %s" % [
		_status,
		_spin_name(),
		_player.is_on_floor(),
		_player.velocity.length(),
		meshed,
		center_offset.length(),
		up_error_deg,
		_player.gravity_acceleration.length(),
		_surface_speed(),
		rad_to_deg(_rotation.angle_rad),
		_anchor_distance_m(),
		RESPAWN_DISTANCE_M,
		_terrain.debug_get_mesh_block_count(),
		_stand_time_s,
		STAND_REPORT_TIMES_S[STAND_REPORT_TIMES_S.size() - 1],
		_stand_drift_m * 1000.0,
		_stand_max_drift_m * 1000.0,
		STAND_TOLERANCE_M * 1000.0,
		_shifts,
		_player.global_position,
	]
	_label.text += "\nSDF at collider hit: %.3f m (about 0 = OK)" % _ground_mismatch_m()
	
	_mismatch_log_s += delta
	if _mismatch_log_s >= 5.0 and not _waiting:
		_mismatch_log_s = 0.0
		print("GroundMismatch: mode=%s surface_speed=%.1f m/s sdf_at_collider_hit=%.4f m" % [_spin_name(), _surface_speed(), _ground_mismatch_m()])
