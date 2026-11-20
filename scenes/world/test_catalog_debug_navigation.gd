extends "res://scenes/world/test_catalog_star_sprites.gd"

const NavData = preload("res://world/debug/lk_debug_navigation_data.gd")
const NavOverlay = preload("res://world/debug/lk_debug_navigation_overlay.gd")
const NavSnapshot = preload("res://world/rendering/lk_far_body_snapshot.gd")

var cpu_nav_state_provider: RefCounted
var _nav_marks: Array = []
var _nav_next_id: int = 1
var _nav_scope: String = ""
var _nav_path: String = ""
var _nav_store_ready: bool = false
var _nav_store_failed: bool = false
var _nav_layout: Dictionary = {}
var _nav_planet_ids: Dictionary = {}
var _nav_records: Array[Dictionary] = []
var _nav_refresh: float = 1.0
var _nav_overlay: NavOverlay
var _nav_show_marks: bool = true
var _nav_show_planets: bool = true
var _nav_show_help: bool = true
var _nav_place_requested: bool = false
var _nav_place_here: bool = false
var _nav_status: String = ""

func _load_target(index: int) -> void:
	super._load_target(index)
	if not _initialised or _failed or is_instance_valid(_nav_overlay):
		return
	if _nav_scope.is_empty():
		_nav_scope = Identity.child_id(_clock_universe_id, "debug_navigation_v1", "%d|%d|%d|%d|%d" % [galaxy_index, sector_x, sector_y, sector_z, system_slot])
		_nav_path = "user://debug_navigation_v1/%s/markers.bin" % _nav_scope
		var loaded: Dictionary = NavData.load_marks(_nav_path, _nav_scope)
		_nav_store_ready = loaded["ok"]
		_nav_store_failed = not _nav_store_ready
		if _nav_store_ready:
			_nav_marks = loaded["marks"]
			_nav_next_id = loaded["next_id"]
		else:
			_nav_status = "Marker store read failed; writing DISABLED: " + str(loaded["error"])
			push_error("DebugNavigation: " + _nav_status)
	if _nav_layout.is_empty():
		var catalog = Catalog.new(_clock_universe_id, _definition.catalog_version)
		_nav_layout = Layout.build(Bodies.build(catalog.describe_system(galaxy_index, sector_x, sector_y, sector_z, system_slot)))
		for entry: Dictionary in _nav_layout["planets"]:
			_nav_planet_ids[entry["body"]["id"]] = int(entry["body"]["slot"])
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 20
	_nav_overlay = NavOverlay.new()
	canvas.add_child(_nav_overlay)
	add_child(canvas)
	_nav_refresh = 1.0
	print("DebugNavigation: ATTACH marks=%d store_ready=%s" % [_nav_marks.size(), _nav_store_ready])

func _close_local_world() -> void:
	_nav_place_requested = false
	_nav_overlay = null # Parent owns/frees all CanvasLayers on a body swap.
	super._close_local_world()

func _commit_nav(marks: Array, next_id: int) -> bool:
	if not _nav_store_ready or not NavData.save_marks(_nav_path, _nav_scope, marks, next_id):
		_nav_status = "Marker write failed/refused; existing marks unchanged"
		push_error("DebugNavigation: " + _nav_status)
		return false
	_nav_marks = marks
	_nav_next_id = next_id
	return true

func _place_navigation_mark() -> void:
	if _nav_marks.size() >= NavData.MAX_MARKS:
		_nav_status = "Marker limit reached (64); remove last with Ctrl+Backspace"
		return
	var camera: Camera3D = _player.player_camera
	var point: Vector3 = _player.global_position
	var surface_hit: bool = false
	if not _nav_place_here:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 512.0, ACTIVE_LAYER, [_player.get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			point = hit["position"]
			surface_hit = true
	var fixed: LkPosition64 = _catalog_frame.inertial_to_body(_frame.to_absolute(point))
	var marks: Array = _nav_marks.duplicate(true)
	marks.append({"serial": _nav_next_id, "body_id": String(_context["body"]["id"]), "q": [fixed.x, fixed.y, fixed.z], "name": "Marker %03d" % _nav_next_id})
	if _commit_nav(marks, _nav_next_id + 1):
		_nav_status = "Placed %s (%s)" % [marks.back()["name"], "terrain hit" if surface_hit else "player position"]
		print("DebugNavigation: " + _nav_status)

func _unhandled_input(event: InputEvent) -> void:
	if _initialised and not _failed and event is InputEventKey and event.pressed and not event.echo:
		# NAV_HOTKEYS_ALT_V1: handle modifiers BEFORE the plain M action.
		if event.alt_pressed and event.keycode in [KEY_M, KEY_P, KEY_H]:
			match event.keycode:
				KEY_M: _nav_show_marks = not _nav_show_marks
				KEY_P: _nav_show_planets = not _nav_show_planets
				KEY_H: _nav_show_help = not _nav_show_help
			get_viewport().set_input_as_handled()
			return
		var handled: bool = true
		match event.keycode:
			KEY_M:
				if not _waiting and not _switching:
					_nav_place_requested = true
					_nav_place_here = event.shift_pressed
			KEY_BACKSPACE:
				if event.ctrl_pressed and not _nav_marks.is_empty():
					var marks: Array = _nav_marks.duplicate(true)
					marks.pop_back()
					if _commit_nav(marks, _nav_next_id):
						_nav_status = "Removed last marker"
				else:
					handled = false
			_: handled = false
		if handled:
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)

func _nav_occluded(relative: Array, distance: float, ignore_body: String = "") -> bool:
	if distance < 0.01:
		return false
	var ray: Array = [relative[0] / distance, relative[1] / distance, relative[2] / distance]
	for record: Dictionary in _nav_records:
		if record["id"] == ignore_body:
			continue
		var hit: float = NavSnapshot.ray_distance(record, ray)
		if hit > 0.0 and hit < distance - 2.0:
			return true
	return false

func _nav_item(relative: Array, name_text: String, marker: bool, blocked: bool, active: bool = false, surface_distance: float = -1.0) -> Dictionary:
	var distance: float = sqrt(float(relative[0]) * float(relative[0]) + float(relative[1]) * float(relative[1]) + float(relative[2]) * float(relative[2]))
	var direction: Vector3 = Vector3(relative[0] / maxf(distance, 1.0e-12), relative[1] / maxf(distance, 1.0e-12), relative[2] / maxf(distance, 1.0e-12))
	var result: Dictionary = NavData.project_direction(_player.player_camera, direction, get_viewport().get_visible_rect().size)
	result.merge({"name": name_text, "marker": marker, "blocked": blocked, "active": active, "distance": NavData.distance_text(distance if surface_distance < 0.0 else surface_distance) + (" to surface" if not marker else "")})
	return result

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_navigation_tick(delta)

func _update_navigation_tick(delta: float) -> void:
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
	# Active-body centre must follow observer EVERY tick, not the 5Hz orbit sample.
	# Otherwise spin/carriage can make nearby marker occlusion flicker.
	for record: Dictionary in _nav_records:
		if not record["active"]:
			continue
		var length: float = sqrt(observer.x * observer.x + observer.y * observer.y + observer.z * observer.z)
		if length > 0.0:
			record["center_m"] = [-observer.x, -observer.y, -observer.z]
			record["direction"] = [-observer.x / length, -observer.y / length, -observer.z / length]
			record["distance_m"] = length
			record["radius_relative"] = float(record["radius_m"]) / length
	var items: Array = []
	var by_id: Dictionary = {}
	for record: Dictionary in _nav_records:
		by_id[record["id"]] = record
		if _nav_planet_ids.has(record["id"]):
			items.append(_nav_item(record["center_m"], "Planet %02d%s" % [_nav_planet_ids[record["id"]] + 1, " [ACTIVE]" if record["active"] else ""], false, _nav_occluded(record["center_m"], record["distance_m"], record["id"]), record["active"], maxf(0.0, float(record["distance_m"]) - float(record["radius_m"]))))
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
				for axis: int in range(3):
					relative.append(float(center[axis]) + float(axes[0][axis]) * float(q[0]) + float(axes[1][axis]) * float(q[1]) + float(axes[2][axis]) * float(q[2]))
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
		items.append(_nav_item(relative, mark["name"], true, blocked))
	_nav_overlay.items = items
	_nav_overlay.marks_visible = _nav_show_marks
	_nav_overlay.planets_visible = _nav_show_planets
	_nav_overlay.queue_redraw()

func _process(delta: float) -> void:
	super._process(delta)
	if _initialised and _nav_show_help:
		_label.text += "\n\nDEBUG NAV | M mark aim | Shift+M mark here | Ctrl+Backspace remove last"
		_label.text += "\nAlt+M marks %s | Alt+P planets %s | Alt+H nav help | saved=%d/64" % [_nav_show_marks, _nav_show_planets, _nav_marks.size()]
		_label.text += "\n" + _nav_status

# NAV_CPU3_PROVIDER_V1
func _navigation_system_states() -> Dictionary:
	if cpu_nav_state_provider != null:
		return cpu_nav_state_provider.call("get_states", _universe_clock.now_s())
	return {}
