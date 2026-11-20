extends "res://scenes/world/test_catalog_approach_activation_fix.gd"

const ShellBridge = preload("res://world/rendering/lk_surface_shell_bridge.gd")
const ShellMath = preload("res://world/debug/lk_surface_shell_math.gd")
var _surface_shell_bridge: ShellBridge
var _publish_max_slope_deg: float = 0.0

func _load_target(index: int) -> void:
	super._load_target(index)
	if not _initialised or _failed or is_instance_valid(_surface_shell_bridge):
		return
	_surface_shell_bridge = ShellBridge.new()
	_surface_shell_bridge.name = "SurfaceShellBridge"
	add_child(_surface_shell_bridge)
	if not _surface_shell_bridge.configure(self, _player.player_camera, _catalog_far_node, _star_sprite_node):
		_fail_gate("cannot configure surface-shell bridge")
		return
	print("SurfaceBoundary: ATTACH stable active entry; inside nominal radius does not suppress sky")

# PUBLISH readiness checks actual data/mesh/colliders, not a hypothetical walk pose.
func _landing_patch_ready() -> bool:
	var started: int = Time.get_ticks_usec()
	var ready: bool = _surface_patch_geometry_ready()
	if _auto_busy:
		var elapsed: int = Time.get_ticks_usec() - started
		_approach_readiness_us += elapsed
		_approach_max_readiness_us = maxi(_approach_max_readiness_us, elapsed)
	return ready

func _surface_patch_geometry_ready() -> bool:
	if not is_instance_valid(_pending):
		_landing_stage = "NO STAGING TERRAIN"
		return false
	var point: Vector3
	var up: Vector3
	if _auto_busy:
		var fixed_up: Vector3 = _auto_target.direction()
		if _auto_aligning:
			point = _fixed_to_local(_auto_target)
			up = _catalog_frame.body_to_inertial(LkPosition64.new(fixed_up.x, fixed_up.y, fixed_up.z)).direction()
		else:
			point = _auto_target.relative_to(_pending_anchor)
			up = fixed_up
	else:
		point = _player.player_camera.global_position
		up = _flight_absolute.direction()
	var basis: Basis = _basis_for_up(up)
	var offsets: Array[Vector3] = [Vector3.ZERO, basis.x * 0.6, -basis.x * 0.6, basis.z * 0.6, -basis.z * 0.6]
	var tool: VoxelToolLodTerrain = _pending.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_SDF
	_publish_max_slope_deg = 0.0
	for offset: Vector3 in offsets:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + offset + up * 48.0, point + offset - up * 96.0, STAGING_LAYER, [_player.get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			_landing_stage = "WAITING COLLIDERS"
			return false
		if _auto_busy and _auto_first_collider_s < 0.0:
			_auto_first_collider_s = _auto_elapsed
			print("AutoSurface: FIRST_COLLIDER seconds=%.2f sandbox=%s" % [_auto_elapsed, not _auto_aligning])
		var local: Vector3 = _pending.to_local(hit["position"])
		var area: AABB = AABB(local - Vector3.ONE * 4.0, Vector3.ONE * 8.0)
		if not tool.is_area_editable(area) or not _pending.is_area_meshed(area, 0):
			_landing_stage = "WAITING FLOOR DATA/MESH"
			return false
		var sdf: float = tool.get_voxel_f_interpolated(local)
		if not is_finite(sdf) or absf(sdf) > 0.1:
			_landing_stage = "COLLIDER/SDF CHECK"
			return false
		var measured: float = ShellMath.slope_degrees(hit["normal"], up)
		if is_finite(measured):
			_publish_max_slope_deg = maxf(_publish_max_slope_deg, measured)
	# No slope or standing-capsule rejection here: rendering is NOT landing.
	_landing_stage = "WORLD READY" if _auto_aligning else "PREFETCH READY"
	if _auto_busy and _auto_warm and not _auto_aligning:
		var height: float = _flight_absolute.length() - float(_context["body"]["radius_m"])
		var gap: float = _actual_surface_point().minus(_auto_target).length()
		if height > _prefetch_activation_height():
			_landing_stage = "READY WAITING APPROACH HEIGHT"
		elif gap > 48.0:
			_landing_stage = "READY RECENTERING ACTUAL FOOTPOINT"
	return true

# Final walking gate: inspect ACTUAL support each tick, then let original chain
# check range, mesh/data, capsule clearance and five stable ticks before release.
func _try_flight_landing() -> void:
	if _flight_active and not _auto_busy and not _landing_preparing and is_instance_valid(_terrain):
		var fixed: LkPosition64 = _catalog_frame.inertial_to_body(_flight_absolute)
		if fixed.minus(_anchor).length() <= 128.0:
			var up: Vector3 = _flight_absolute.direction()
			var point: Vector3 = _player.global_position
			var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + up * 0.1, point - up * 8.0, ACTIVE_LAYER, [_player.get_rid()])
			var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty():
				var slope: float = ShellMath.slope_degrees(hit["normal"], up)
				if not is_finite(slope):
					_refuse_flight_landing("invalid support normal; choose another spot")
					return
				if slope > _player.floor_max_angle_deg:
					_refuse_flight_landing("support slope %.2f deg exceeds %.2f deg; terrain is active, move to flatter ground" % [slope, _player.floor_max_angle_deg])
					return
	super._try_flight_landing()

func _refuse_flight_landing(reason: String) -> void:
	super._refuse_flight_landing(reason)
	print("WalkGate: REFUSED " + reason)

func _close_local_world() -> void:
	if is_instance_valid(_surface_shell_bridge):
		remove_child(_surface_shell_bridge)
		_surface_shell_bridge.queue_free()
		_surface_shell_bridge = null
	super._close_local_world()

func _process(delta: float) -> void:
	super._process(delta)
	if _initialised and _flight_show_telemetry and is_instance_valid(_surface_shell_bridge):
		_label.text += "\nSURFACE BOUNDARY signed camera height %.4f m | publish != walk" % _surface_shell_bridge.signed_height_m

func _promote_landing_patch() -> void:
	var previous: VoxelLodTerrain = _terrain
	super._promote_landing_patch()
	if is_instance_valid(_terrain) and _terrain != previous:
		print("SurfaceReadiness: ACTIVE probe_slope_max_deg=%.2f; walk pose requires separate G checks" % _publish_max_slope_deg)
