extends "res://scenes/world/test_catalog_surface_control_v5.gd"

const ContactPolicy6 = preload("res://world/debug/lk_surface_contact_policy.gd")
@export var contact_timeout_s: float = 2.0
@export var contact_clearance_m: float = 0.03
var _contact6_active: bool = false
var _contact6_cancel_requested: bool = false
var _contact6_elapsed: float = 0.0
var _contact6_stable: int = 0
var _contact6_body: String = ""
var _contact6_note: String = ""

func _try_flight_landing() -> void:
	if _contact6_active:
		return
	# Retain V5's assisted weak-gravity path and its G-to-cruise behavior.
	var sample: Dictionary = _control5_gravity_sample()
	if _control5_assisted or not sample["valid"]:
		super._try_flight_landing()
		return
	if SurfacePolicy5.classify(sample["g"], low_gravity_assist_threshold) != "NORMAL":
		super._try_flight_landing()
		return
	if _auto_busy or _landing_preparing or is_instance_valid(_pending) or _movement_paused or _stream_hold:
		_refuse_flight_landing("wait for active live terrain before contact acquisition")
		return
	var fixed: LkPosition64 = _catalog_frame.inertial_to_body(_flight_absolute)
	if fixed.minus(_anchor).length() > 128.0 or not _terrain.visible or _terrain.collision_layer != ACTIVE_LAYER:
		_refuse_flight_landing("wait for nearby live AUTO patch")
		return
	var up: Vector3 = _flight_absolute.direction()
	var point: Vector3 = _player.global_position
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + up * 0.1, point - up * 8.0, ACTIVE_LAYER, [_player.get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		_flight_exit_ticks = 0
		_flight_status = "CONTACT6 waits for live floor ray; G cancels"
		return
	var ground: Vector3 = hit["position"]
	var hover: float = (point - ground).dot(up)
	if hover < 1.0 or hover > 4.0:
		_refuse_flight_landing("hover 1..4 m above actual live terrain")
		return
	var normal: Vector3 = hit["normal"]
	var cosine: float = normal.dot(up)
	if cosine < cos(deg_to_rad(_player.floor_max_angle_deg)):
		_refuse_flight_landing("floor too steep for physical contact")
		return
	var local: Vector3 = _terrain.to_local(ground)
	var area: AABB = AABB(local - Vector3.ONE * 4.0, Vector3.ONE * 8.0)
	if not _terrain.is_area_meshed(area, 0) or not _voxel_tool.is_area_editable(area):
		_flight_exit_ticks = 0
		_flight_status = "CONTACT6 waits for live floor data/mesh; G cancels"
		return
	var height: float = ContactPolicy6.center_height(_capsule.height, _capsule.radius, cosine, contact_clearance_m)
	if not is_finite(height) or contact_clearance_m <= 0.02 or contact_clearance_m / cosine >= _player.floor_snap_length:
		_refuse_flight_landing("contact clearance must exceed query margin and remain within floor snap")
		return
	var basis: Basis = _player._basis_from_up(up, _flight_basis)
	var target: Vector3 = ground + up * height
	var probe: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	probe.shape = _capsule
	probe.transform = Transform3D(basis, target)
	probe.collision_mask = ACTIVE_LAYER
	probe.exclude = [_player.get_rid()]
	probe.margin = 0.02
	if not get_world_3d().direct_space_state.intersect_shape(probe, 1).is_empty():
		_refuse_flight_landing("contact candidate capsule overlaps geometry")
		return
	_flight_exit_ticks += 1
	if _flight_exit_ticks < 5:
		_flight_status = "CONTACT6 candidate checks %d/5" % _flight_exit_ticks
		return
	_contact6_active = true
	_contact6_cancel_requested = false
	_contact6_elapsed = 0.0
	_contact6_stable = 0
	_contact6_body = String(_context["body"]["id"])
	_contact6_note = "ACQUIRING support; walking and reanchor not released"
	_flight_landing_requested = false
	_flight_exit_ticks = 0
	_player.global_transform = Transform3D(basis, target)
	_player.camera_pivot.transform = _flight_saved_pivot
	_player.player_camera.transform = _flight_saved_camera
	_player.velocity = Vector3.ZERO
	_player.up_direction = up
	_player.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	_player.dominant_body_id = StringName(_contact6_body)
	_player.collision_layer = 2
	_player.collision_mask = ACTIVE_LAYER
	_player.attach_to_frame(_catalog_frame)
	_player.set_controllable(true) # Required by inherited rotation carry only.
	_player.set_physics_process(false) # One explicit native movement pass below.
	_player.reset_physics_interpolation()
	_flight_absolute = _frame.to_absolute(_player.global_position)
	print("SurfaceContact6: BEGIN body=%s g=%.9f clearance=%.4f capsule_center_height=%.4f walking_reanchor=false" % [_contact6_body, sample["g"], contact_clearance_m, height])

func _physics_process(delta: float) -> void:
	if _contact6_active:
		_contact6_tick(delta)
		return
	super._physics_process(delta)

# Temporary acquisition owns this tick. Do not ALSO run ancestor clock/player
# callbacks. Clock progresses once; native player callback remains disabled.
func _contact6_tick(delta: float) -> void:
	if _failed:
		return
	if not _universe_clock.advance(delta):
		_fail_gate("SurfaceContact6 clock rejected delta")
		return
	var step: float = _catalog_frame.advance(0.0)
	_update_terrain_transform()
	_player.carry_with_frame(_catalog_frame, step, float(_context["body"]["physical_bound_radius_m"]) + 1000.0)
	_flight_absolute = _frame.to_absolute(_player.global_position)
	if _contact6_cancel_requested:
		_contact6_abort("cancelled by G")
		return
	if String(_context["body"]["id"]) != _contact6_body or is_instance_valid(_pending) or _auto_busy:
		_contact6_abort("body or publication changed")
		return
	var sample: Dictionary = _gravity.sample(_flight_absolute, StringName(_contact6_body), _player.gravity_switch_ratio)
	var acceleration: Vector3 = sample["acceleration"]
	if not acceleration.is_finite() or not sample["has_up"] or SurfacePolicy5.classify(acceleration.length(), low_gravity_assist_threshold) != "NORMAL":
		_contact6_abort("gravity no longer suitable; remain protected, G may select assist")
		return
	var up: Vector3 = sample["up"]
	_player.up_direction = up
	_player.gravity_acceleration = acceleration
	_player.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	# No walking input or artificial gravity. Manual snap is a bounded contact
	# placement operation, only during acquisition, not permanent adhesion.
	_player.velocity = acceleration * delta
	_player.move_and_slide()
	if not _player.is_on_floor():
		_player.apply_floor_snap()
	_flight_absolute = _frame.to_absolute(_player.global_position)
	_update_terrain_transform()
	var floor_ok: bool = _player.is_on_floor()
	if floor_ok:
		floor_ok = _player.get_floor_normal().dot(up) >= cos(deg_to_rad(_player.floor_max_angle_deg))
	var live_ok: bool = floor_ok and _flight_local_terrain_ready()
	_contact6_stable = _contact6_stable + 1 if live_ok else 0
	_contact6_elapsed += delta
	_contact6_note = "ACQUIRING floor=%s data_ready=%s stable=%d/5 t=%.2f" % [floor_ok, live_ok, _contact6_stable, _contact6_elapsed]
	_update_stellar_lighting()
	_update_navigation_tick(delta)
	_clock_autosave_s += delta
	if _clock_autosave_s >= 30.0:
		_clock_autosave_s = 0.0
		if not SharedClockStore.save_clock(_clock_universe_id, _universe_clock):
			_fail_gate("SurfaceContact6 clock autosave failed")
			return
	if _contact6_stable >= 5:
		_contact6_finish()
	elif _contact6_elapsed >= maxf(contact_timeout_s, 0.1):
		_contact6_abort("support timeout; no walking/reanchor release")

func _contact6_finish() -> void:
	_contact6_active = false
	_control5_assisted = false
	_flight_active = false
	_flight_landing_requested = false
	_flight_exit_ticks = 0
	_player.velocity = Vector3.ZERO
	_player.set_controllable(true)
	_player.set_physics_process(true)
	_player.reset_physics_interpolation()
	_terrain.visible = true
	_terrain.collision_layer = ACTIVE_LAYER
	_release_auto_viewer()
	_contact6_note = "SUPPORTED: physical walking released after actual floor checks"
	_flight_status = _contact6_note
	print("SurfaceContact6: SUPPORTED body=%s seconds=%.3f stable=5/5 on_floor=true" % [_contact6_body, _contact6_elapsed])
	print("DebugFlight: LANDED body=%s revision=%d" % [_context["body"]["id"], _edit_journal.get_revision()])

func _contact6_abort(reason: String) -> void:
	# Preserve CURRENT camera pose, not the historical pre-contact position.
	var camera: Camera3D = _player.player_camera
	var point: LkPosition64 = _frame.to_absolute(camera.global_position)
	var basis: Basis = camera.global_basis.orthonormalized()
	_contact6_active = false
	_contact6_cancel_requested = false
	_player.set_physics_process(false)
	_player.set_controllable(false)
	_player.detach_from_frame()
	_player.velocity = Vector3.ZERO
	_player.collision_layer = 0
	_player.collision_mask = 0
	_player.camera_pivot.transform = Transform3D.IDENTITY
	camera.transform = Transform3D.IDENTITY
	_flight_active = true
	_flight_landing_requested = false
	_flight_exit_ticks = 0
	_flight_absolute = point
	_flight_basis = basis
	if not _place_flight_absolute(point):
		_fail_gate("SurfaceContact6 could not restore protected flight")
		return
	_contact6_note = "CONTACT REFUSED: " + reason + "; protected flight retained"
	_flight_status = _contact6_note
	print("SurfaceContact6: ABORT %s body=%s walking_reanchor=false" % [reason, _context["body"]["id"]])

func _unhandled_input(event: InputEvent) -> void:
	if _contact6_active:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G and not event.ctrl_pressed and not event.alt_pressed:
			_contact6_cancel_requested = true
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _close_local_world() -> void:
	_contact6_active = false
	_contact6_cancel_requested = false
	super._close_local_world()

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(_control5_label) and _contact6_active:
		_control5_label.text += "\nCONTACT6: " + _contact6_note + " | G cancels"
		var view: Vector2 = get_viewport().get_visible_rect().size
		_control5_label.position.y = maxf(16.0, view.y - _control5_label.get_minimum_size().y - 14.0)

func _prefetch_should_start(height: float, closing: float) -> bool:
	if _contact6_active:
		return false
	return super._prefetch_should_start(height, closing)
