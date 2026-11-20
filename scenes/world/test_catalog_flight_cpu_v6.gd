extends "res://scenes/world/test_catalog_flight_cpu_v5.gd"

const PackedPool = preload("res://world/debug/lk_flight_sphere_pool_packed.gd")
const PackedMath = preload("res://world/debug/lk_debug_flight_math_packed.gd")

@export var cpu6_packed_spheres_enabled: bool = true
@export var cpu6_fast_navigation_enabled: bool = true
var _cpu6_packed_pool: PackedPool
var _cpu6_packed_valid: bool = false
var _cpu6_packed_centers: PackedFloat64Array = PackedFloat64Array()
var _cpu6_packed_radii: PackedFloat64Array = PackedFloat64Array()
var _cpu6_items: Array = []
var _cpu6_by_id: Dictionary = {}
var _cpu6_planet_labels: Dictionary = {}

func _load_target(index: int) -> void:
	super._load_target(index)
	if not _initialised or _failed or _cpu6_packed_pool != null and _cpu6_packed_pool.valid:
		return
	_cpu6_packed_pool = PackedPool.new()
	if not _cpu6_packed_pool.configure(_nav_layout, String(_context["body"]["id"])):
		_fail_gate("CPU6 cannot bind packed sphere metadata")
		return
	_cpu6_planet_labels.clear()
	for id: String in _nav_planet_ids.keys():
		_cpu6_planet_labels[id] = "Planet %02d" % (_nav_planet_ids[id] + 1)
	_cpu6_items.clear()
	_cpu6_by_id.clear()
	_cpu6_packed_valid = false
	print("FlightCPU6: BIND packed=%s fast_nav=%s exact-epoch states unchanged" % [cpu6_packed_spheres_enabled, cpu6_fast_navigation_enabled])

func _flight_spheres() -> Array:
	if not cpu6_packed_spheres_enabled:
		return super._flight_spheres()
	var sphere_us: int = Time.get_ticks_usec() if flight_sphere_sections_enabled else 0
	var states: Dictionary = _flight_system_states()
	sphere_us = _flight_sphere_boundary("states", sphere_us)
	if states.is_empty():
		_fail_gate("empty flight system states")
		return []
	var local_ready: bool = _flight_local_terrain_ready()
	sphere_us = _flight_sphere_boundary("terrain_readiness", sphere_us)
	if _cpu6_packed_pool == null:
		_fail_gate("CPU6 packed pool missing")
		return []
	var ok: bool = _cpu6_packed_pool.build_packed(states, _flight_absolute, _universe_clock.now_s(), local_ready)
	sphere_us = _flight_sphere_boundary("relative_build", sphere_us)
	if not ok:
		_fail_gate("CPU6 packed sphere pool rejected state: " + _cpu6_packed_pool.error)
		return []
	_flight_height = _cpu6_packed_pool.nearest_height
	_flight_reference = _cpu6_packed_pool.nearest_label
	_cpu6_packed_centers = _cpu6_packed_pool.centers
	_cpu6_packed_radii = _cpu6_packed_pool.radii
	_cpu6_packed_valid = true
	return [] # Packed buffers are consumed by _flight_safe_step below.

func _flight_safe_step(direction: Vector3, requested: float, spheres: Variant) -> float:
	if cpu6_packed_spheres_enabled and _cpu6_packed_valid:
		return PackedMath.safe_step_packed(direction, requested, _cpu6_packed_centers, _cpu6_packed_radii)
	return super._flight_safe_step(direction, requested, spheres)

func _update_navigation_tick(delta: float) -> void:
	if not cpu6_fast_navigation_enabled:
		super._update_navigation_tick(delta)
		return
	if not _initialised or _waiting or _failed or not is_instance_valid(_nav_overlay):
		return
	if _nav_place_requested:
		_nav_place_requested = false
		_place_navigation_mark()
	var camera: Camera3D = _player.player_camera
	var observer: LkPosition64 = _frame.to_absolute(camera.global_position)
	_nav_refresh += delta
	if _nav_refresh >= 0.2:
		_nav_refresh = 0.0
		_nav_records = NavSnapshot.build(_nav_layout, String(_context["body"]["id"]), observer, _universe_clock.now_s(), _navigation_system_states())
	for record: Dictionary in _nav_records:
		if not record["active"]:
			continue
		var length: float = sqrt(observer.x * observer.x + observer.y * observer.y + observer.z * observer.z)
		if length > 0.0:
			record["center_m"] = [-observer.x, -observer.y, -observer.z]
			record["direction"] = [-observer.x / length, -observer.y / length, -observer.z / length]
			record["distance_m"] = length
			record["radius_relative"] = float(record["radius_m"]) / length
	var items: Array = _cpu6_items
	var by_id: Dictionary = _cpu6_by_id
	items.clear()
	by_id.clear()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if _nav_show_planets:
		for record: Dictionary in _nav_records:
			by_id[record["id"]] = record
			if not _nav_planet_ids.has(record["id"]):
				continue
			var distance: float = sqrt(float(record["center_m"][0]) * float(record["center_m"][0]) + float(record["center_m"][1]) * float(record["center_m"][1]) + float(record["center_m"][2]) * float(record["center_m"][2]))
			var label: String = _cpu6_planet_labels[record["id"]]
			if record["active"]:
				label += " [ACTIVE]"
			var blocked: bool = _nav_occluded(record["center_m"], record["distance_m"], record["id"])
			items.append(_nav_item_fast(record["center_m"], distance, label, false, blocked, record["active"], maxf(0.0, float(record["distance_m"]) - float(record["radius_m"])), camera, viewport_size))
	if _nav_show_marks:
		for mark: Dictionary in _nav_marks:
			var q: Array = mark["q"]
			var relative: Array = []
			if mark["body_id"] == _context["body"]["id"]:
				var rotated: LkPosition64 = _catalog_frame.body_to_inertial(LkPosition64.new(q[0], q[1], q[2]))
				relative = [rotated.x - observer.x, rotated.y - observer.y, rotated.z - observer.z]
			else:
				if not by_id.has(mark["body_id"]):
					continue
				var found: bool = false
				for context: Dictionary in _targets:
					if context["body"]["id"] != mark["body_id"]:
						continue
					var axes: Array = OrbitMotion.spin_state(context["spin"], _universe_clock.now_s())["body_to_system_axes"]
					var center: Array = by_id[mark["body_id"]]["center_m"]
					relative = [
						float(center[0]) + float(axes[0][0]) * float(q[0]) + float(axes[1][0]) * float(q[1]) + float(axes[2][0]) * float(q[2]),
						float(center[1]) + float(axes[0][1]) * float(q[0]) + float(axes[1][1]) * float(q[1]) + float(axes[2][1]) * float(q[2]),
						float(center[2]) + float(axes[0][2]) * float(q[0]) + float(axes[1][2]) * float(q[1]) + float(axes[2][2]) * float(q[2]),
					]
					found = true
					break
				if not found:
					continue
			var distance: float = sqrt(float(relative[0]) * float(relative[0]) + float(relative[1]) * float(relative[1]) + float(relative[2]) * float(relative[2]))
			var blocked: bool = _nav_occluded(relative, distance)
			if not blocked and distance > 2.0 and distance < 512.0:
				var end: Vector3 = camera.global_position + Vector3(relative[0], relative[1], relative[2]) * float((distance - 0.5) / distance)
				var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(camera.global_position, end, ACTIVE_LAYER, [_player.get_rid()])
				blocked = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
			items.append(_nav_item_fast(relative, distance, mark["name"], true, blocked, false, -1.0, camera, viewport_size))
	_nav_overlay.items = items
	_nav_overlay.marks_visible = _nav_show_marks
	_nav_overlay.planets_visible = _nav_show_planets
	_nav_overlay.queue_redraw()

func _nav_item_fast(relative: Array, distance: float, name_text: String, marker: bool, blocked: bool, active: bool, surface_distance: float, camera: Camera3D, viewport_size: Vector2) -> Dictionary:
	var direction: Vector3 = Vector3(float(relative[0]) / maxf(distance, 1.0e-12), float(relative[1]) / maxf(distance, 1.0e-12), float(relative[2]) / maxf(distance, 1.0e-12))
	var result: Dictionary = NavData.project_direction(camera, direction, viewport_size)
	result["name"] = name_text
	result["marker"] = marker
	result["blocked"] = blocked
	result["active"] = active
	result["distance"] = NavData.distance_text(distance if surface_distance < 0.0 else surface_distance) + (" to surface" if not marker else "")
	return result

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.alt_pressed and event.keycode == KEY_P:
		cpu6_packed_spheres_enabled = not cpu6_packed_spheres_enabled
		_cpu6_packed_valid = false
		print("FlightCPU6: packed=%s; sphere sections reset" % cpu6_packed_spheres_enabled)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.alt_pressed and event.keycode == KEY_N:
		cpu6_fast_navigation_enabled = not cpu6_fast_navigation_enabled
		print("FlightCPU6: fast_nav=%s; navigation sections reset" % cpu6_fast_navigation_enabled)
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _close_local_world() -> void:
	_cpu6_packed_pool = null
	_cpu6_packed_valid = false
	_cpu6_items.clear()
	_cpu6_by_id.clear()
	super._close_local_world()

func _process(delta: float) -> void:
	super._process(delta)
	if _initialised and _flight_show_telemetry:
		_label.text += "\nFLIGHT CPU6 packed %s | fast nav %s | Alt+P spheres / Alt+N nav" % [cpu6_packed_spheres_enabled, cpu6_fast_navigation_enabled]
