extends "res://scenes/world/test_catalog_debug_flight.gd"

const LandingPolicy = preload("res://world/debug/lk_landing_patch_policy.gd")

@export var landing_patch_timeout_s: float = 90.0
var _landing_preparing: bool = false
var _landing_delta: float = 0.0
var _landing_revision: int = -1
var _landing_stage: String = "IDLE"
var _landing_progress_s: float = 0.0

func _enter_flight() -> void:
	super._enter_flight()
	if _flight_active:
		_flight_status = "G near surface: prepare a new landing patch or restore walking"

func _choose_anchor(fixed: LkPosition64) -> LkPosition64:
	if _landing_preparing:
		var planned: Dictionary = LandingPolicy.plan(fixed, _anchor_lattice_origin, ANCHOR_GRID_M)
		if planned["ok"]:
			return planned["anchor"]
	return super._choose_anchor(fixed)

func _update_terrain_transform() -> void:
	super._update_terrain_transform()
	if _landing_preparing and is_instance_valid(_pending):
		_set_patch_transform(_pending, _pending_anchor)
		# The old departure patch can be hidden, but staging needs this viewer.
		if is_instance_valid(_flight_viewer):
			_flight_viewer.requires_visuals = true
			_flight_viewer.requires_collisions = true

func _tick_flight(delta: float) -> void:
	_landing_delta = delta
	if _landing_preparing and not _flight_landing_requested:
		_cancel_landing_patch("cancelled by G")
	super._tick_flight(delta)

func _try_flight_landing() -> void:
	if _landing_preparing:
		_poll_landing_patch()
		return
	var fixed: LkPosition64 = _catalog_frame.inertial_to_body(_flight_absolute)
	if fixed.minus(_anchor).length() <= 128.0:
		super._try_flight_landing()
		return
	var height: float = _flight_absolute.length() - float(_context["body"]["radius_m"])
	if not LandingPolicy.can_prepare(height):
		_refuse_flight_landing("for new terrain descend to 0.5..64 m above the mean sphere, then G")
		return
	if is_instance_valid(_pending):
		_refuse_flight_landing("another terrain build is active")
		return
	if not _save_journal():
		_refuse_flight_landing("cannot save journal before terrain preparation")
		return
	_landing_revision = _edit_journal.get_revision()
	_landing_preparing = true
	_landing_stage = "BUILD"
	_landing_progress_s = 0.0
	_start_build()
	# Floor is about32m below hover in this debug pass; keep it at LOD0.
	_pending.lod_distance = 96.0
	_pending.visible = false
	_update_terrain_transform()
	_flight_status = "Preparing new terrain; translation held, G cancels"
	print("LandingPatch: PREPARE body=%s revision=%d anchor=(%.3f,%.3f,%.3f)" % [_context["body"]["id"], _landing_revision, _pending_anchor.x, _pending_anchor.y, _pending_anchor.z])

func _poll_landing_patch() -> void:
	if not is_instance_valid(_pending):
		_cancel_landing_patch("staging terrain missing")
		return
	_pending_time_s += _landing_delta
	_landing_progress_s += _landing_delta
	var pending_generator: EditedGenerator = _pending.generator as EditedGenerator
	if pending_generator == null or _edit_journal.get_revision() != _landing_revision or pending_generator.get_revision() != _landing_revision:
		_cancel_landing_patch("journal revision changed")
		return
	var old_stage: String = _landing_stage
	var ready: bool = _landing_patch_ready()
	if ready:
		_pending_stable_ticks += 1
	else:
		_pending_stable_ticks = 0
	if old_stage != _landing_stage or _landing_progress_s >= 2.0:
		_landing_progress_s = 0.0
		print("LandingPatch: WAIT seconds=%.2f stage=%s data=%d mesh=%d stable=%d/5" % [_pending_time_s, _landing_stage, _pending.debug_get_data_block_count(), _pending.debug_get_mesh_block_count(), _pending_stable_ticks])
	_flight_status = "Landing patch %s | %.1f s | stable %d/5 | G cancels" % [_landing_stage, _pending_time_s, _pending_stable_ticks]
	if _pending_stable_ticks >= 5:
		_promote_landing_patch()
	elif _pending_time_s > maxf(1.0, landing_patch_timeout_s):
		_cancel_landing_patch("timeout: " + _landing_stage)

func _landing_patch_ready() -> bool:
	var point: Vector3 = _player.player_camera.global_position
	var up: Vector3 = _flight_absolute.direction()
	var basis: Basis = _basis_for_up(up)
	var offsets: Array[Vector3] = [Vector3.ZERO, basis.x * 0.6, -basis.x * 0.6, basis.z * 0.6, -basis.z * 0.6]
	var tool: VoxelToolLodTerrain = _pending.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_SDF
	var ground: Vector3
	for i: int in range(offsets.size()):
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + offsets[i] + up * 4.0, point + offsets[i] - up * 96.0, STAGING_LAYER, [_player.get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			_landing_stage = "WAITING FOR GROUND COLLIDERS"
			return false
		var hit_point: Vector3 = hit["position"]
		var local: Vector3 = _pending.to_local(hit_point)
		var area: AABB = AABB(local - Vector3.ONE * 4.0, Vector3.ONE * 8.0)
		if not tool.is_area_editable(area) or not _pending.is_area_meshed(area, 0):
			_landing_stage = "WAITING FOR FLOOR DATA/MESH"
			return false
		var sdf: float = tool.get_voxel_f_interpolated(local)
		if not is_finite(sdf) or absf(sdf) > 0.1:
			_landing_stage = "COLLIDER/SDF NOT READY"
			return false
		var normal: Vector3 = hit["normal"]
		if normal.dot(up) < cos(deg_to_rad(_player.floor_max_angle_deg)):
			_landing_stage = "SLOPE TOO STEEP; G CANCELS"
			return false
		if i == 0:
			ground = hit_point
	var probe: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	probe.shape = _capsule
	probe.transform = Transform3D(_player._basis_from_up(up, _flight_basis), ground + up * 1.4)
	probe.collision_mask = STAGING_LAYER
	probe.exclude = [_player.get_rid()]
	probe.margin = 0.02
	if not get_world_3d().direct_space_state.intersect_shape(probe, 1).is_empty():
		_landing_stage = "CAPSULE BLOCKED; G CANCELS"
		return false
	_landing_stage = "READY"
	return true

func _promote_landing_patch() -> void:
	# Final checks before discarding old terrain; NO old/new collider comparison:
	# the old patch does not cover this new location.
	if _edit_journal.get_revision() != _landing_revision or not _landing_patch_ready():
		_pending_stable_ticks = 0
		return
	if not _save_journal():
		_cancel_landing_patch("save failed before promotion")
		return
	var before_position: Vector3 = _player.global_position
	var before_velocity: Vector3 = _player.velocity
	var elapsed: float = _pending_time_s
	var generator: EditedGenerator = _pending.generator as EditedGenerator
	var old: VoxelLodTerrain = _terrain
	remove_child(old)
	_terrain = _pending
	_anchor = _pending_anchor.copy()
	_pending = null
	_terrain.collision_layer = ACTIVE_LAYER
	_terrain.collision_mask = 1
	_terrain.visible = true
	_terrain.force_update_transform()
	_voxel_tool = _terrain.get_voxel_tool()
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	_voxel_tool.set_raycast_binary_search_iterations(8)
	old.queue_free()
	_reanchors += 1
	_swap_position_error_m = _player.global_position.distance_to(before_position)
	_swap_velocity_error_mps = _player.velocity.distance_to(before_velocity)
	_last_profile_error_m = NAN # No overlapping old patch; not a measured zero.
	_pending_stable_ticks = 0
	_landing_preparing = false
	_flight_landing_requested = false
	_flight_exit_ticks = 0
	_landing_stage = "PATCH ACTIVE"
	_flight_status = "New terrain active. Descend to 1..4 m above it, then G to walk"
	_print_snapshot_cache_stats("LANDING", generator)
	print("LandingPatch: ACTIVE body=%s revision=%d seconds=%.2f player_shift_m=%.9f old_profile_reference=none" % [_context["body"]["id"], _landing_revision, elapsed, _swap_position_error_m])

func _cancel_landing_patch(reason: String) -> void:
	if _landing_preparing and is_instance_valid(_pending):
		remove_child(_pending)
		_pending.queue_free()
		_pending = null
	_pending_stable_ticks = 0
	_landing_preparing = false
	_flight_landing_requested = false
	_flight_exit_ticks = 0
	_landing_stage = "CANCELLED"
	_flight_status = "Landing preparation cancelled: " + reason
	print("LandingPatch: CANCEL reason=%s; previous terrain retained; flight remains active" % reason)

func _close_local_world() -> void:
	if _landing_preparing:
		_cancel_landing_patch("world closing")
	super._close_local_world()

func _process(delta: float) -> void:
	super._process(delta)
	if _initialised and _flight_show_telemetry:
		_label.text += "\nLAND ANYWHERE: G at <=64m prepares patch; descend, G walks | same body only"
