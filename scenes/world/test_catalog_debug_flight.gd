extends "res://scenes/world/test_catalog_debug_navigation.gd"

const FlightMath = preload("res://world/debug/lk_debug_flight_math.gd")
const FlightCarry = preload("res://world/debug/lk_debug_flight_carry.gd")

@export var debug_flight_mouse_sensitivity: float = 0.003
# Earth-reference midpoint; adaptive sizing enabled by default.
@export var debug_flight_carry_height_m: float = 250000.0
@export var debug_flight_adaptive_carry: bool = true
@export var debug_flight_carry_override_m: float = 0.0
var _flight_carry_band: Dictionary = {}
var _flight_carry_weight: float = 0.0
var flight_cpu_sections_enabled: bool = false
var flight_sphere_sections_enabled: bool = false
var _flight_active: bool = false
var _flight_toggle_requested: bool = false
var _flight_multiplier: float = 1.0
var _flight_absolute: LkPosition64
var _flight_basis: Basis
var _flight_saved_pivot: Transform3D
var _flight_saved_camera: Transform3D
var _flight_show_telemetry: bool = true
var _flight_actual_speed: float = 0.0
var _flight_requested_speed: float = 0.0
var _flight_reference: String = ""
var _flight_height: float = 0.0
var _flight_status: String = "G: toggle debug flight / exit to walk-EVA"
var _flight_descriptors: Dictionary = {}
var _flight_viewer: VoxelViewer
var _flight_exit_ticks: int = 0
var _flight_landing_requested: bool = false

func _enter_flight() -> void:
	if _waiting or _stream_hold:
		_flight_status = "Flight refused: wait for stable terrain"
		return
	# Debug Flight must always be available, even after a terrain/reanchor failure.
	_failed = false
	var camera: Camera3D = _player.player_camera
	var absolute: LkPosition64 = _frame.to_absolute(camera.global_position)
	if absolute.length() - float(_context["body"]["radius_m"]) < 0.5:
		_flight_status = "Flight entry requires open surface, outside the mean sphere"
		return
	if not _save_journal():
		_flight_status = "Flight refused: save failed"
		return
	_flight_absolute = absolute
	_flight_basis = camera.global_basis.orthonormalized()
	_flight_saved_pivot = _player.camera_pivot.transform
	_flight_saved_camera = camera.transform
	_player.set_controllable(false)
	_player.set_physics_process(false)
	_player.detach_from_frame()
	_player.velocity = Vector3.ZERO
	_player.collision_layer = 0
	_player.collision_mask = 0
	_player.camera_pivot.transform = Transform3D.IDENTITY
	camera.transform = Transform3D.IDENTITY
	for child: Node in _player.get_children():
		if child is VoxelViewer:
			_flight_viewer = child
	_flight_descriptors.clear()
	_flight_descriptors[_nav_layout["star"]["id"]] = _nav_layout["star"]
	for entry: Dictionary in _nav_layout["planets"]:
		_flight_descriptors[entry["body"]["id"]] = entry["body"]
		for moon: Dictionary in entry["moons"]:
			_flight_descriptors[moon["body"]["id"]] = moon["body"]
	_flight_active = true
	_request_stamp = false
	_flight_status = "FLIGHT: G exits to walk/EVA by local gravity"
	if not _place_flight_absolute(_flight_absolute):
		_fail_gate("flight absolute-position adapter failed")
	print("DebugFlight: ENTER body=%s" % _context["body"]["id"])

func _place_flight_absolute(point: LkPosition64) -> bool:
	# CoordinateFrame forbids large shift_by(). Reinitialize origin only after
	# unregistering its single player root. Keep SAME frame object for renderers.
	_frame.unregister_root(_player)
	if not _frame.initialize_origin(point):
		_frame.register_root(_player)
		return false
	_player.global_position = Vector3.ZERO
	_player.global_basis = _flight_basis
	_player.reset_physics_interpolation()
	_frame.register_root(_player)
	_update_terrain_transform()
	return true

func _update_terrain_transform() -> void:
	if _flight_active and _flight_absolute != null and is_instance_valid(_terrain):
		var near_patch: bool = (_flight_absolute.length() - float(_context["body"]["radius_m"]) < 4096.0
			and _catalog_frame.inertial_to_body(_flight_absolute).minus(_anchor).length() < 8192.0)
		_terrain.visible = near_patch
		_terrain.collision_layer = ACTIVE_LAYER if near_patch else 0
		if is_instance_valid(_flight_viewer):
			_flight_viewer.requires_visuals = near_patch
			_flight_viewer.requires_collisions = near_patch
		if not near_patch:
			return # Do not move distant terrain colliders through huge float positions.
	super._update_terrain_transform()

func _flight_spheres() -> Array:
	var sphere_us: int = Time.get_ticks_usec() if flight_sphere_sections_enabled else 0
	var states: Dictionary = _flight_system_states()
	sphere_us = _flight_sphere_boundary("states", sphere_us)
	if states.is_empty():
		_fail_gate("empty flight system states")
		return []
	var local_ready: bool = _flight_local_terrain_ready()
	sphere_us = _flight_sphere_boundary("terrain_readiness", sphere_us)
	var result: Array = _build_flight_body_spheres(states, local_ready)
	sphere_us = _flight_sphere_boundary("relative_build", sphere_us)
	return result

func _flight_local_terrain_ready() -> bool:
	if not _terrain.visible or _terrain.collision_layer != ACTIVE_LAYER:
		return false
	var fixed: LkPosition64 = _catalog_frame.inertial_to_body(_flight_absolute)
	if fixed.minus(_anchor).length() > 128.0:
		return false
	var point: Vector3 = _player.global_position
	var up: Vector3 = _flight_absolute.direction()
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + up * 0.1, point - up * 64.0, ACTIVE_LAYER, [_player.get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return false
	var local: Vector3 = _terrain.to_local(hit["position"])
	var area: AABB = AABB(local - Vector3.ONE * 4.0, Vector3.ONE * 8.0)
	return _terrain.is_area_meshed(area, 0) and _voxel_tool.is_area_editable(area)

func _tick_flight(delta: float) -> void:
	var _cpu_us: int = Time.get_ticks_usec() if flight_cpu_sections_enabled else 0
	# FLIGHT_ADAPTIVE_CARRY_V1
	var body: Dictionary = _context["body"]
	_flight_carry_band = FlightCarry.band(float(body["radius_m"]), float(body["surface_gravity_m_s2"]), debug_flight_carry_height_m, debug_flight_adaptive_carry, debug_flight_carry_override_m)
	_flight_carry_weight = FlightCarry.weight(_flight_absolute.length() - float(body["radius_m"]), _flight_carry_band)
	if not _universe_clock.advance(delta):
		_fail_gate("flight clock rejected delta")
		return
	_catalog_frame.advance(0.0)
	if _flight_carry_weight > 0.0:
		var carry_angle: float = _catalog_frame.angular_speed_rad_s * delta * _flight_carry_weight
		_flight_absolute = _flight_absolute.plus(_catalog_frame.carry_displacement64(_flight_absolute, carry_angle))
		_flight_basis = (_catalog_frame.step_basis(carry_angle) * _flight_basis).orthonormalized()
	_cpu_us = _flight_cpu_boundary("clock_carry", _cpu_us)
	if not _place_flight_absolute(_flight_absolute):
		_fail_gate("flight relocation failed")
		return
	_cpu_us = _flight_cpu_boundary("place_before", _cpu_us)
	var spheres: Variant = _flight_spheres()
	if _failed:
		return # Fail closed before any movement if sphere data was rejected.
	_cpu_us = _flight_cpu_boundary("spheres", _cpu_us)
	var boost: float = 4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	_flight_requested_speed = _flight_speed_at_height(_flight_height, _flight_multiplier * boost)
	var input_vector: Vector3 = Vector3.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _flight_landing_requested:
		input_vector.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		input_vector.y = float(Input.is_physical_key_pressed(KEY_SPACE)) - float(Input.is_physical_key_pressed(KEY_C))
		input_vector.z = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	var direction: Vector3 = (_flight_basis * input_vector).normalized()
	var requested: float = _flight_requested_speed * delta if input_vector.length_squared() > 0.0 else 0.0
	var allowed: float = _flight_safe_step(direction, requested, spheres)
	var direction64: Array = FlightMath.unit_direction(direction)
	if allowed > 0.0:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(_player.player_camera.global_position, _player.player_camera.global_position + direction * minf(allowed, 4096.0), ACTIVE_LAYER, [_player.get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			allowed = minf(allowed, maxf(0.0, Vector3(hit["position"]).distance_to(_player.player_camera.global_position) - 1.0))
	_flight_absolute = LkPosition64.new(_flight_absolute.x + float(direction64[0]) * allowed, _flight_absolute.y + float(direction64[1]) * allowed, _flight_absolute.z + float(direction64[2]) * allowed)
	_flight_actual_speed = allowed / delta
	_cpu_us = _flight_cpu_boundary("movement_guard", _cpu_us)
	if not _place_flight_absolute(_flight_absolute):
		_fail_gate("flight relocation failed after movement")
		return
	_cpu_us = _flight_cpu_boundary("place_after", _cpu_us)
	_update_stellar_lighting()
	_cpu_us = _flight_cpu_boundary("lighting", _cpu_us)
	_update_navigation_tick(delta)
	_cpu_us = _flight_cpu_boundary("navigation", _cpu_us)
	_clock_autosave_s += delta
	if _clock_autosave_s >= 30.0:
		_clock_autosave_s = 0.0
		if not SharedClockStore.save_clock(_clock_universe_id, _universe_clock):
			_fail_gate("flight clock autosave failed")
	if _flight_landing_requested:
		_try_flight_landing()
	_cpu_us = _flight_cpu_boundary("tail", _cpu_us)

func _refuse_flight_landing(reason: String) -> void:
	_flight_status = "Walk refused: " + reason
	_flight_exit_ticks = 0
	_flight_landing_requested = false

func _try_flight_landing() -> void:
	if is_instance_valid(_pending):
		_refuse_flight_landing("terrain publication pending")
		return
	var up: Vector3 = _flight_absolute.direction()
	var point: Vector3 = _player.global_position
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + up * 0.1, point - up * 8.0, ACTIVE_LAYER, [_player.get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		_flight_status = "Landing waits for terrain collision; G exits to walk/EVA"
		_flight_exit_ticks = 0
		return
	var ground: Vector3 = hit["position"]
	var height: float = (point - ground).dot(up)
	if height < 1.0 or height > 4.0:
		_refuse_flight_landing("hover 1..4 m above terrain")
		return
	var local: Vector3 = _terrain.to_local(ground)
	var area: AABB = AABB(local - Vector3.ONE * 4.0, Vector3.ONE * 8.0)
	if not _terrain.is_area_meshed(area, 0) or not _voxel_tool.is_area_editable(area):
		_flight_status = "Landing waits for terrain data/mesh; G exits to walk/EVA"
		_flight_exit_ticks = 0
		return
	var basis: Basis = _player._basis_from_up(up, _flight_basis)
	var target: Vector3 = ground + up * 1.4
	var probe: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	probe.shape = _capsule
	probe.transform = Transform3D(basis, target)
	probe.collision_mask = ACTIVE_LAYER
	probe.exclude = [_player.get_rid()]
	probe.margin = 0.02
	if not get_world_3d().direct_space_state.intersect_shape(probe, 1).is_empty():
		_refuse_flight_landing("capsule overlaps terrain")
		return
	_flight_exit_ticks += 1
	if _flight_exit_ticks < 5:
		_flight_status = "Landing stable checks %d/5" % _flight_exit_ticks
		return
	_player.global_transform = Transform3D(basis, target)
	_player.camera_pivot.transform = _flight_saved_pivot
	_player.player_camera.transform = _flight_saved_camera
	_player.velocity = Vector3.ZERO
	_player.up_direction = up
	_player.dominant_body_id = StringName(_context["body"]["id"])
	_player.collision_layer = 2
	_player.collision_mask = ACTIVE_LAYER
	_player.attach_to_frame(_catalog_frame)
	_player.set_controllable(true)
	_player.set_physics_process(true)
	_player.reset_physics_interpolation()
	_flight_active = false
	_flight_landing_requested = false
	_flight_exit_ticks = 0
	_terrain.visible = true
	_terrain.collision_layer = ACTIVE_LAYER
	_flight_status = "WALK restored after five collision-ready ticks"
	print("DebugFlight: LANDED body=%s revision=%d" % [_context["body"]["id"], _edit_journal.get_revision()])

# G exits Debug Flight anywhere ONLY when the active terrain is actually meshed
# below the player. After auto-handover the live terrain may still be inactive
# (collision_layer=0, visible=false) if AutoSurface cancelled; exiting then
# leaves the player with no collision and they fall through the planet.
# A downward raycast against ACTIVE_LAYER gates the exit; if no mesh is found,
# Debug Flight stays active with a clear status instead of dropping the player
# into a void.
func _exit_flight_direct() -> void:
	var up: Vector3 = _flight_absolute.direction()
	var point: Vector3 = _player.global_position
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + up * 0.1, point - up * 64.0, ACTIVE_LAYER, [_player.get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		_flight_status = "EXIT refused: no active terrain mesh below; keep flying or wait for surface"
		print("DebugFlight: EXIT_REFUSED body=%s no terrain below" % _context["body"]["id"])
		return
	_player.camera_pivot.transform = _flight_saved_pivot
	_player.player_camera.transform = _flight_saved_camera
	_player.velocity = Vector3.ZERO
	_player.up_direction = up
	_player.dominant_body_id = StringName(_context["body"]["id"])
	_player.collision_layer = 2
	_player.collision_mask = ACTIVE_LAYER
	_player.attach_to_frame(_catalog_frame)
	_player.set_controllable(true)
	_player.set_physics_process(true)
	_player.reset_physics_interpolation()
	if is_instance_valid(_flight_viewer):
		_flight_viewer.requires_visuals = true
		_flight_viewer.requires_collisions = true
	_flight_active = false
	_flight_landing_requested = false
	_flight_exit_ticks = 0
	_flight_status = "EXIT: walk/EVA by local gravity"
	print("DebugFlight: EXIT_DIRECT body=%s" % _context["body"]["id"])

func _physics_process(delta: float) -> void:
	if _flight_toggle_requested:
		_flight_toggle_requested = false
		if _flight_active:
			_exit_flight_direct()
		else:
			_enter_flight()
	if _flight_active:
		if not _failed:
			_tick_flight(delta)
		return
	super._physics_process(delta)

func _unhandled_input(event: InputEvent) -> void:
	if _initialised and not _failed:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_G and not event.alt_pressed and not event.ctrl_pressed:
				_flight_toggle_requested = true
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_V and event.alt_pressed:
				_flight_show_telemetry = not _flight_show_telemetry
				get_viewport().set_input_as_handled()
				return
		if _flight_active:
			if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_flight_basis = (_flight_basis * Basis(Vector3.UP, -event.relative.x * debug_flight_mouse_sensitivity) * Basis(Vector3.RIGHT, -event.relative.y * debug_flight_mouse_sensitivity)).orthonormalized()
				_player.global_basis = _flight_basis
				get_viewport().set_input_as_handled()
				return
			if event is InputEventMouseButton and event.pressed:
				if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
					_flight_multiplier = clampf(_flight_multiplier * (2.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.5), 1.0 / 1024.0, 1024.0)
					get_viewport().set_input_as_handled()
					return
				if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
					return # Editing intentionally disabled in diagnostic flight.
			if event is InputEventKey and event.pressed and not event.echo:
				if event.keycode in [KEY_1, KEY_2]:
					_flight_status = "Land before switching isolated body worlds"
					return
				if event.keycode == KEY_BACKSLASH:
					_flight_multiplier = 1.0
					return
	super._unhandled_input(event)

func _close_local_world() -> void:
	_flight_active = false
	_flight_toggle_requested = false
	_flight_landing_requested = false
	_flight_viewer = null
	super._close_local_world()

func _process(delta: float) -> void:
	super._process(delta)
	if _initialised and _flight_show_telemetry:
		_label.text += "\n\nDEBUG FLIGHT %s | G toggle / exit walk-EVA | Alt+V telemetry" % _flight_active
		_label.text += "\nWASD + mouse | Space up / C down | wheel x2 / x0.5 | Shift x4 | Backslash reset"
		if _flight_active:
			_label.text += "\nSpeed %s/s | target %s/s | multiplier x%.3f" % [NavData.distance_text(_flight_actual_speed), NavData.distance_text(_flight_requested_speed), _flight_multiplier]
			_label.text += "\nNearest surface %s | reference %s | local frame, not orbital physics" % [NavData.distance_text(maxf(0.0, _flight_height)), _flight_reference]
		if _flight_active and _flight_carry_band.get("ok", false):
			_label.text += "\nSurface carry %.1f%% | transition %.2f..%.2f km | active body" % [_flight_carry_weight * 100.0, float(_flight_carry_band["inner_m"]) / 1000.0, float(_flight_carry_band["outer_m"]) / 1000.0]
		_label.text += "\n" + _flight_status

# FLIGHT_CPU3_HOOKS_V1
func _flight_system_states() -> Dictionary:
	return Layout.evaluate(_nav_layout, _universe_clock.now_s())

func _flight_cpu_boundary(section: String, started: int) -> int:
	if not flight_cpu_sections_enabled:
		return 0
	var now: int = Time.get_ticks_usec()
	_flight_cpu_section(section, now - started)
	return now

func _flight_cpu_section(_section: String, _elapsed_us: int) -> void:
	pass

# FLIGHT_SPHERE_CPU4_HOOKS_V1: original builder retained as default.
func _build_flight_body_spheres(states: Dictionary, local_ready: bool) -> Array:
	var active_position: Array = []
	for state: Dictionary in states["bodies"]:
		if state["id"] == _context["body"]["id"]:
			active_position = state["position_m"]
			break
	var spheres: Array = []
	_flight_height = INF
	for state: Dictionary in states["bodies"]:
		var center: Array = [-_flight_absolute.x, -_flight_absolute.y, -_flight_absolute.z]
		if state["id"] != _context["body"]["id"]:
			for axis: int in range(3):
				center[axis] += float(state["position_m"][axis]) - float(active_position[axis])
		var radius: float = _flight_descriptors[state["id"]]["radius_m"]
		var distance: float = sqrt(float(center[0]) * float(center[0]) + float(center[1]) * float(center[1]) + float(center[2]) * float(center[2]))
		var height: float = distance - radius
		if height < _flight_height:
			_flight_height = height
			_flight_reference = String(state["id"]).left(8)
		var guard_radius: float = radius
		if state["id"] != _context["body"]["id"] or not local_ready:
			guard_radius += 32.0
		spheres.append({"center": center, "radius": guard_radius})
	return spheres

func _flight_sphere_boundary(section: String, started: int) -> int:
	if not flight_sphere_sections_enabled:
		return 0
	var now: int = Time.get_ticks_usec()
	_flight_sphere_section(section, now - started)
	return now

func _flight_sphere_section(_section: String, _elapsed_us: int) -> void:
	pass

# FLIGHT_CPU6_HOOKS_V1: default movement guard remains original FlightMath.safe_step.
func _flight_safe_step(direction: Vector3, requested: float, spheres: Variant) -> float:
	return FlightMath.safe_step(direction, requested, spheres)

# SURFACE_CONTROL5_SPEED_HOOK_V1: legacy scenes keep exact original speed.
func _flight_speed_at_height(height: float, multiplier: float) -> float:
	return FlightMath.speed_at_height(height, multiplier)
