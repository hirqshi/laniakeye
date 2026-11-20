extends "res://scenes/world/test_catalog_landing_patch.gd"

const AutoPolicy = preload("res://world/debug/lk_auto_surface_policy.gd")

@export var auto_surface_enabled: bool = true
@export var auto_surface_horizon_s: float = 30.0
@export var auto_surface_max_height_m: float = 1000000.0
@export var auto_surface_hover_height_m: float = 1500.0
@export var auto_surface_stable_target_s: float = 0.2
@export var auto_surface_view_distance_m: int = 96

var _auto_busy: bool = false
var _auto_warm: bool = false
var _auto_aligning: bool = false
var _auto_target: LkPosition64
var _auto_candidate: LkPosition64
var _auto_candidate_s: float = 0.0
var _auto_retry_s: float = 0.0
var _auto_viewer: VoxelViewer
var _auto_elapsed: float = 0.0
var _auto_align_s: float = 0.0
var _auto_first_collider_s: float = -1.0
var _auto_last_height: float = NAN
var _auto_last_stage: String = ""

func _enter_flight() -> void:
	super._enter_flight()
	_auto_last_height = NAN
	_auto_candidate = null
	_auto_candidate_s = 0.0
	if _flight_active:
		_flight_status = "Automatic terrain preparation enabled; G only requests walking" if auto_surface_enabled else "Manual terrain preparation: G"

func _auto_limit() -> float:
	# Start in full active-body carry, so a selected geographic point remains stable.
	var band: Dictionary = FlightCarry.band(float(_context["body"]["radius_m"]), float(_context["body"]["surface_gravity_m_s2"]), debug_flight_carry_height_m, debug_flight_adaptive_carry, debug_flight_carry_override_m)
	if not band["ok"]:
		return 1500.0
	return maxf(64.0, minf(maxf(64.0, auto_surface_max_height_m), float(band["inner_m"]) * 0.95))

func _flight_spheres() -> Array:
	var spheres: Array = super._flight_spheres()
	if auto_surface_enabled:
		var height: float = _flight_absolute.length() - float(_context["body"]["radius_m"])
		var limit: float = _auto_limit()
		if height > limit + 2.0:
			# At enormous debug speeds don't skip the approach-entry zone entirely.
			spheres.append({"center": [-_flight_absolute.x, -_flight_absolute.y, -_flight_absolute.z], "radius": float(_context["body"]["radius_m"]) + limit - 1.0})
	return spheres

func _choose_anchor(fixed: LkPosition64) -> LkPosition64:
	if _auto_busy and _auto_target != null:
		return LandingPolicy.plan(_auto_target, _anchor_lattice_origin, ANCHOR_GRID_M)["anchor"]
	return super._choose_anchor(fixed)

func _update_terrain_transform() -> void:
	super._update_terrain_transform()
	if _auto_busy and is_instance_valid(_pending):
		if _auto_aligning:
			_set_patch_transform(_pending, _pending_anchor)
		else:
			# Hidden collision-layer4 staging sandbox in body-fixed axes near zero.
			# Avoid astronomical float transforms while camera is far above ground.
			_set_prefetch_sandbox_transform()
		if is_instance_valid(_flight_viewer):
			_flight_viewer.requires_visuals = false
			_flight_viewer.requires_collisions = false
		_position_auto_viewer()
	elif is_instance_valid(_auto_viewer):
		if not _flight_active or _auto_target == null or _catalog_frame.inertial_to_body(_flight_absolute).minus(_auto_target).length() > 4096.0:
			_release_auto_viewer()
		else:
			_position_auto_viewer()

func _position_auto_viewer() -> void:
	if not is_instance_valid(_auto_viewer) or _auto_target == null:
		return
	var fixed_up: Vector3 = _auto_target.direction()
	if _auto_busy and not _auto_aligning:
		_auto_viewer.global_position = _auto_target.relative_to(_pending_anchor) + fixed_up * 16.0
	else:
		var world_up: Vector3 = _catalog_frame.body_to_inertial(LkPosition64.new(fixed_up.x, fixed_up.y, fixed_up.z)).direction()
		_auto_viewer.global_position = _fixed_to_local(_auto_target) + world_up * 16.0

func _release_auto_viewer() -> void:
	if is_instance_valid(_auto_viewer):
		remove_child(_auto_viewer)
		_auto_viewer.queue_free()
		_auto_viewer = null

func _tick_flight(delta: float) -> void:
	# Keep the validated flight/clock/carry/navigation tick; auto work never sets
	# the manual landing-request flag, so translation remains available.
	super._tick_flight(delta)
	if not _flight_active or _failed:
		_release_auto_viewer()
		return
	if not auto_surface_enabled:
		return
	_auto_retry_s = maxf(0.0, _auto_retry_s - delta)
	var radius: float = _context["body"]["radius_m"]
	var height: float = _flight_absolute.length() - radius
	var closing: float = 0.0
	if is_finite(_auto_last_height):
		closing = (_auto_last_height - height) / delta
	_auto_last_height = height
	var target_result: Dictionary = _prefetch_surface_target(radius)
	if not target_result["ok"]:
		return
	var target: LkPosition64 = target_result["point"]
	if _auto_busy:
		if _prefetch_target_invalid(target, height):
			_cancel_landing_patch("left target region")
			return
		_poll_auto_surface(delta)
		return
	if _landing_preparing or is_instance_valid(_pending):
		return
	if _auto_target != null and is_instance_valid(_auto_viewer) and AutoPolicy.in_target(target, _auto_target, 48.0):
		return
	if AutoPolicy.in_target(target, _anchor, 64.0) and _flight_local_terrain_ready():
		return
	if _auto_retry_s > 0.0 or not _prefetch_should_start(height, closing):
		_auto_candidate_s = 0.0
		_auto_candidate = null
		return
	if _auto_candidate == null or not AutoPolicy.in_target(target, _auto_candidate, 32.0):
		_auto_candidate = target
		_auto_candidate_s = 0.0
		return
	_auto_candidate_s += delta
	if _auto_candidate_s >= maxf(0.0, auto_surface_stable_target_s):
		_start_auto_surface(target, height, closing)

func _start_auto_surface(target: LkPosition64, height: float, closing: float) -> void:
	_release_auto_viewer()
	_auto_target = target.copy()
	_auto_busy = true
	_auto_warm = false
	_auto_aligning = false
	_auto_elapsed = 0.0
	_auto_align_s = 0.0
	_auto_first_collider_s = -1.0
	_landing_revision = _edit_journal.get_revision()
	_auto_last_stage = ""
	_auto_candidate_s = 0.0
	if is_instance_valid(_flight_viewer):
		_flight_viewer.requires_visuals = false
		_flight_viewer.requires_collisions = false
	_start_build()
	_pending.lod_distance = 32.0
	_pending.view_distance = clampi(auto_surface_view_distance_m, 64, 128)
	_pending.visible = false
	_pending.collision_layer = STAGING_LAYER
	_pending.collision_mask = 0
	_auto_viewer = VoxelViewer.new()
	_auto_viewer.name = "AutoSurfacePrefetchViewer"
	_auto_viewer.view_distance = clampi(auto_surface_view_distance_m, 64, 128)
	_auto_viewer.requires_visuals = true
	_auto_viewer.requires_collisions = true
	add_child(_auto_viewer)
	_update_terrain_transform()
	print("AutoSurface: START height_m=%.1f closing_mps=%.1f lead_s=%.1f view=%d lod_distance=32 revision=%d" % [height, closing, height / maxf(closing, 0.1), _auto_viewer.view_distance, _landing_revision])

func _poll_auto_surface(delta: float) -> void:
	_auto_elapsed += delta
	_pending_time_s = _auto_elapsed
	_landing_progress_s += delta
	if not is_instance_valid(_pending):
		_cancel_landing_patch("missing staging terrain")
		return
	var generator: EditedGenerator = _pending.generator as EditedGenerator
	if generator == null or generator.get_revision() != _landing_revision or _edit_journal.get_revision() != _landing_revision:
		_cancel_landing_patch("journal revision mismatch")
		return
	var ready: bool = _landing_patch_ready()
	_pending_stable_ticks = _pending_stable_ticks + 1 if ready else 0
	if _auto_aligning:
		_auto_align_s += delta
	if _landing_stage != _auto_last_stage or _landing_progress_s >= 2.0:
		_auto_last_stage = _landing_stage
		_landing_progress_s = 0.0
		print("AutoSurface: WAIT seconds=%.2f stage=%s data=%d mesh=%d stable=%d/5" % [_auto_elapsed, _landing_stage, _pending.debug_get_data_block_count(), _pending.debug_get_mesh_block_count(), _pending_stable_ticks])
	if _pending_stable_ticks >= 5:
		_promote_landing_patch()
	elif (not _auto_warm and _auto_elapsed > maxf(1.0, landing_patch_timeout_s)) or (_auto_aligning and _auto_align_s > 30.0):
		_cancel_landing_patch("readiness timeout: " + _landing_stage)
	if _auto_busy:
		_flight_status = "AUTO SURFACE %s %.1fs | flying remains available | Alt+L toggles auto" % [_landing_stage, _auto_elapsed]

func _landing_patch_ready() -> bool:
	if not _auto_busy:
		return super._landing_patch_ready()
	var fixed_up: Vector3 = _auto_target.direction()
	var point: Vector3
	var up: Vector3
	if _auto_aligning:
		point = _fixed_to_local(_auto_target)
		up = _catalog_frame.body_to_inertial(LkPosition64.new(fixed_up.x, fixed_up.y, fixed_up.z)).direction()
	else:
		point = _auto_target.relative_to(_pending_anchor)
		up = fixed_up
	var basis: Basis = _basis_for_up(up)
	var offsets: Array[Vector3] = [Vector3.ZERO, basis.x * 0.6, -basis.x * 0.6, basis.z * 0.6, -basis.z * 0.6]
	var tool: VoxelToolLodTerrain = _pending.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_SDF
	var ground: Vector3
	for i: int in range(offsets.size()):
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + offsets[i] + up * 48.0, point + offsets[i] - up * 48.0, STAGING_LAYER, [_player.get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			_landing_stage = "WAITING COLLIDERS"
			return false
		if _auto_first_collider_s < 0.0:
			_auto_first_collider_s = _auto_elapsed
			print("AutoSurface: FIRST_COLLIDER seconds=%.2f sandbox=%s" % [_auto_elapsed, not _auto_aligning])
		var p: Vector3 = hit["position"]
		var local: Vector3 = _pending.to_local(p)
		var area: AABB = AABB(local - Vector3.ONE * 4.0, Vector3.ONE * 8.0)
		if not tool.is_area_editable(area) or not _pending.is_area_meshed(area, 0):
			_landing_stage = "WAITING FLOOR DATA/MESH"
			return false
		var sdf: float = tool.get_voxel_f_interpolated(local)
		if not is_finite(sdf) or absf(sdf) > 0.1:
			_landing_stage = "COLLIDER/SDF CHECK"
			return false
		var normal: Vector3 = hit["normal"]
		if normal.dot(up) < cos(deg_to_rad(_player.floor_max_angle_deg)):
			_landing_stage = "TARGET TOO STEEP"
			return false
		if i == 0:
			ground = p
	var shape: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	shape.shape = _capsule
	shape.transform = Transform3D(_basis_for_up(up), ground + up * 1.4)
	shape.collision_mask = STAGING_LAYER
	shape.exclude = [_player.get_rid()]
	shape.margin = 0.02
	if not get_world_3d().direct_space_state.intersect_shape(shape, 1).is_empty():
		_landing_stage = "TARGET CAPSULE BLOCKED"
		return false
	_landing_stage = "WORLD READY" if _auto_aligning else "PREFETCH READY"
	return true

func _promote_landing_patch() -> void:
	if not _auto_busy:
		super._promote_landing_patch()
		return
	if not _auto_warm:
		_auto_warm = true
		print("AutoSurface: WARM seconds=%.2f data=%d mesh=%d" % [_auto_elapsed, _pending.debug_get_data_block_count(), _pending.debug_get_mesh_block_count()])
	var height: float = _flight_absolute.length() - float(_context["body"]["radius_m"])
	var point: LkPosition64 = AutoPolicy.surface_target(_catalog_frame.inertial_to_body(_flight_absolute), float(_context["body"]["radius_m"]))["point"]
	if height > _prefetch_activation_height() or not AutoPolicy.in_target(point, _auto_target, 48.0):
		return
	if not _auto_aligning:
		_auto_aligning = true
		_auto_align_s = 0.0
		_pending_stable_ticks = 0
		_update_terrain_transform()
		print("AutoSurface: ALIGN height_m=%.2f; rechecking actual-world colliders" % height)
		return
	# Parent repeats readiness, preserves player, saves, swaps and reports stats.
	super._promote_landing_patch()
	if _pending == null:
		_auto_busy = false
		_auto_warm = false
		_auto_aligning = false
		_terrain.view_distance = _prefetch_promoted_view_distance()
		_terrain.lod_distance = 32.0
		if is_instance_valid(_auto_viewer):
			_auto_viewer.view_distance = _prefetch_promoted_view_distance()
		_update_terrain_transform()
		_flight_status = "AUTO terrain active. Descend to1..4m, G only to walk"
		print("AutoSurface: ACTIVE total_seconds=%.2f; no G required for preparation" % _auto_elapsed)

func _try_flight_landing() -> void:
	if not auto_surface_enabled:
		super._try_flight_landing()
		return
	if _auto_busy:
		_refuse_flight_landing("automatic terrain preparation is still running; flying remains available")
		return
	var fixed: LkPosition64 = _catalog_frame.inertial_to_body(_flight_absolute)
	if fixed.minus(_anchor).length() > 128.0:
		_refuse_flight_landing("wait for AUTO terrain, then G at1..4m; no manual build needed")
		return
	super._try_flight_landing()
	if not _flight_active:
		_release_auto_viewer()

func _cancel_landing_patch(reason: String) -> void:
	if not _auto_busy:
		super._cancel_landing_patch(reason)
		return
	if is_instance_valid(_pending):
		remove_child(_pending)
		_pending.queue_free()
		_pending = null
	_auto_busy = false
	_auto_warm = false
	_auto_aligning = false
	_auto_retry_s = 2.0
	_auto_candidate = null
	_auto_candidate_s = 0.0
	_pending_stable_ticks = 0
	_release_auto_viewer()
	_update_terrain_transform()
	_flight_status = "Auto terrain cancelled: " + reason
	print("AutoSurface: CANCEL reason=%s; previous terrain retained" % reason)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.alt_pressed and event.keycode == KEY_L:
		auto_surface_enabled = not auto_surface_enabled
		_auto_last_height = NAN
		if _auto_busy and not auto_surface_enabled:
			_cancel_landing_patch("disabled by Alt+L")
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _close_local_world() -> void:
	if _auto_busy:
		_cancel_landing_patch("world closing")
	_release_auto_viewer()
	super._close_local_world()

func _process(delta: float) -> void:
	super._process(delta)
	if _initialised and _flight_show_telemetry:
		if auto_surface_enabled:
			_label.text = _label.text.replace("\nLAND ANYWHERE: G at <=64m prepares patch; descend, G walks | same body only", "")
		_label.text += "\nAUTO SURFACE %s | Alt+L | preparation needs NO G; G only walks" % auto_surface_enabled

# PREFETCH_HOOKS_V1: defaults preserve original scene behavior.
func _prefetch_surface_target(radius: float) -> Dictionary:
	return AutoPolicy.surface_target(_catalog_frame.inertial_to_body(_flight_absolute), radius)

func _prefetch_target_invalid(target: LkPosition64, height: float) -> bool:
	return not AutoPolicy.in_target(target, _auto_target, 96.0) or height > _auto_limit() * 1.2

func _prefetch_should_start(height: float, closing: float) -> bool:
	return AutoPolicy.should_start(height, closing, _auto_limit(), maxf(1.0, auto_surface_horizon_s), maxf(1.0, auto_surface_hover_height_m))

func _prefetch_activation_height() -> float:
	return 512.0

# FRAME_PACING_VIEW_HOOK_V1: legacy scenes keep their original view.
func _prefetch_promoted_view_distance() -> int:
	return 192

# PACING_SANDBOX_HOOK_V2: preserve legacy default behavior.
func _set_prefetch_sandbox_transform() -> void:
	_pending.global_transform = Transform3D.IDENTITY
	_pending.force_update_transform()
