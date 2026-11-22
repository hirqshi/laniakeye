class_name LkUniverseSpatial
extends RefCounted

const Galaxies = preload("res://game/world/generation/lk_galaxy_placement.gd")
const GalaxyValidator = preload("res://game/world/generation/lk_galaxy_placement_validator.gd")
const Catalog = preload("res://game/world/generation/lk_world_catalog.gd")
const Bodies = preload("res://game/world/generation/lk_body_catalog.gd")
const Orbits = preload("res://game/world/generation/lk_safe_orbit_layout.gd")
const Systems = preload("res://game/world/generation/lk_system_placement.gd")
const OrbitValidator = preload("res://game/world/generation/lk_orbit_layout_validator.gd")

const VERSION: int = 1
const LY_M: float = Systems.LIGHT_YEAR_M
const BOUNDARY_PAD_LY: float = 1.0e-8
const LAYOUT_CACHE_CAPACITY: int = 16
static var _layouts: Dictionary = {}
static var _layout_keys: Array[String] = []
static var _layout_cursor: int = 0
static var _layout_builds: int = 0
static var _layout_hits: int = 0
static var _layout_mutex: Mutex = Mutex.new()


static func clear_layout_cache() -> void:
	_layout_mutex.lock()
	_layouts.clear()
	_layout_keys.clear()
	_layout_cursor = 0
	_layout_builds = 0
	_layout_hits = 0
	_layout_mutex.unlock()


static func layout_cache_stats() -> Dictionary:
	_layout_mutex.lock()
	var report: Dictionary = {"resident": _layouts.size(), "builds": _layout_builds, "hits": _layout_hits}
	_layout_mutex.unlock()
	return report


# Cache only generation, not address validation or galaxy containment.
# Compare complete descriptors; ID equality alone must not hide changed inputs.
static func _layout_for(source: Dictionary) -> Dictionary:
	var key: String = String(source.get("id", ""))
	_layout_mutex.lock()
	if _layouts.has(key) and _layouts[key]["source"] == source:
		_layout_hits += 1
		var cached: Dictionary = _layouts[key]["layout"].duplicate(true)
		_layout_mutex.unlock()
		return cached
	_layout_builds += 1
	_layout_mutex.unlock()
	var layout: Dictionary = Orbits.build(Bodies.build(source))
	if layout.is_empty() or not OrbitValidator.validate(layout).is_empty():
		return {}
	_layout_mutex.lock()
	if not _layouts.has(key):
		if _layout_keys.size() < LAYOUT_CACHE_CAPACITY:
			_layout_keys.append(key)
		else:
			_layouts.erase(_layout_keys[_layout_cursor])
			_layout_keys[_layout_cursor] = key
			_layout_cursor = (_layout_cursor + 1) % LAYOUT_CACHE_CAPACITY
	_layouts[key] = {"source": source.duplicate(true), "layout": layout.duplicate(true)}
	_layout_mutex.unlock()
	return layout


static func _failure(code: String) -> Dictionary:
	return {"ok": false, "code": code}


# Reject distant sector indices in INTEGER space before any huge int -> float
# conversion or x+1 arithmetic. Only near-envelope coordinates reach the AABB.
static func sector_may_intersect(galaxy: Dictionary, x: int, y: int, z: int) -> bool:
	var radius: float = galaxy["envelope_radius_ly"]
	var limit: int = int(ceil(radius / Catalog.SECTOR_WIDTH_LY)) + 1
	var squared: float = 0.0
	for coordinate: int in [x, y, z]:
		if coordinate < -limit or coordinate > limit:
			return false
		var lo: float = float(coordinate) * Catalog.SECTOR_WIDTH_LY
		var hi: float = lo + Catalog.SECTOR_WIDTH_LY
		var nearest: float = lo if lo > 0.0 else (hi if hi < 0.0 else 0.0)
		squared += nearest * nearest
	return squared <= radius * radius


static func _system_center_ly(placement: Dictionary) -> Array[float]:
	var result: Array[float] = []
	for axis: int in range(3):
		var key: String = ["x", "y", "z"][axis]
		var sector: int = String(placement["sector_address"][key]).to_int()
		result.append(float(sector) * Catalog.SECTOR_WIDTH_LY + float(placement["offset_m"][axis]) / LY_M)
	return result


static func _locate(source: Dictionary, galaxy: Dictionary, universe_id: String, x: int, y: int, z: int) -> Dictionary:
	var layout: Dictionary = _layout_for(source)
	if layout.is_empty():
		return _failure("invalid_orbit_layout")
	var placement: Dictionary = Systems.place(source, layout, galaxy["galaxy_id"], x, y, z)
	if placement.is_empty() or not Systems.validate(placement, source, layout, galaxy["galaxy_id"], x, y, z).is_empty():
		return _failure("invalid_system_placement")
	var center: Array[float] = _system_center_ly(placement)
	var radius: float = float(placement["system_bound_m"]) / LY_M
	if not Galaxies.contains_local_sphere(galaxy, center, radius + BOUNDARY_PAD_LY):
		return _failure("outside_galaxy")
	return {"ok": true, "location": {
		"spatial_version": VERSION, "universe_id": universe_id,
		"galaxy": galaxy.duplicate(true), "system": placement,
	}}


static func resolve_system(definition, galaxy_index: int, x: int, y: int, z: int, slot: int) -> Dictionary:
	if definition.catalog_version != 1 or galaxy_index < 0 or slot < 0 or slot >= Catalog.MAX_SYSTEMS_PER_SECTOR:
		return _failure("invalid_address_or_version")
	var universe: String = definition.get_universe_id()
	var galaxy: Dictionary = Galaxies.describe_galaxy(universe, galaxy_index)
	if galaxy.is_empty() or not GalaxyValidator.validate(galaxy, universe).is_empty():
		return _failure("invalid_galaxy")
	if not sector_may_intersect(galaxy, x, y, z):
		return _failure("outside_galaxy")
	var catalog = Catalog.new(universe, definition.catalog_version)
	var source: Dictionary = catalog.describe_system(galaxy_index, x, y, z, slot)
	if source.is_empty():
		return _failure("unknown_system")
	return _locate(source, galaxy, universe, x, y, z)


# Successful empty query is distinct from invalid generation. Boundary systems
# outside the galaxy are filtered; any other generation error fails the query.
static func resolve_sector(definition, galaxy_index: int, x: int, y: int, z: int) -> Dictionary:
	if definition.catalog_version != 1 or galaxy_index < 0:
		return _failure("invalid_address_or_version")
	var universe: String = definition.get_universe_id()
	var galaxy: Dictionary = Galaxies.describe_galaxy(universe, galaxy_index)
	if galaxy.is_empty() or not GalaxyValidator.validate(galaxy, universe).is_empty():
		return _failure("invalid_galaxy")
	var locations: Array[Dictionary] = []
	if not sector_may_intersect(galaxy, x, y, z):
		return {"ok": true, "outside_galaxy": true, "locations": locations, "filtered": 0, "source_count": 0}
	var catalog = Catalog.new(universe, definition.catalog_version)
	var sector: Dictionary = catalog.describe_sector(galaxy_index, x, y, z)
	if sector.is_empty():
		return _failure("invalid_sector")
	var filtered: int = 0
	for source: Dictionary in sector["systems"]:
		var located: Dictionary = _locate(source, galaxy, universe, x, y, z)
		if located["ok"]:
			locations.append(located["location"])
		elif located["code"] == "outside_galaxy":
			filtered += 1
		else:
			return located
	return {"ok": true, "outside_galaxy": false, "locations": locations,
		"filtered": filtered, "source_count": sector["systems"].size()}


static func _point_valid(location: Dictionary, point: Array) -> bool:
	if point.size() != 3:
		return false
	var squared: float = 0.0
	for component in point:
		if not is_finite(float(component)):
			return false
		squared += float(component) * float(component)
	return sqrt(squared) <= float(location["system"]["system_bound_m"])


static func _inverse_rotate(galaxy: Dictionary, vector: Array) -> Array[float]:
	var result: Array[float] = []
	var axes: Array = galaxy["galaxy_to_universe_axes"]
	for i: int in range(3):
		result.append(float(axes[i][0]) * float(vector[0]) + float(axes[i][1]) * float(vector[1]) + float(axes[i][2]) * float(vector[2]))
	return result


static func _length(vector: Array) -> float:
	return sqrt(float(vector[0]) * float(vector[0]) + float(vector[1]) * float(vector[1]) + float(vector[2]) * float(vector[2]))


# Locations must come from resolve_system/resolve_sector and be treated immutable.
# Points are offsets from the system's central star, in unrotated GALAXY axes,
# in metres. An observer on a planet supplies orbit_position + local camera offset.
# Sector/system offsets are NEVER passed as point offsets.
static func relative(target: Dictionary, observer: Dictionary,
	target_point_m: Array = [0.0, 0.0, 0.0], observer_point_m: Array = [0.0, 0.0, 0.0]) -> Dictionary:
	if target.get("spatial_version", -1) != VERSION or observer.get("spatial_version", -1) != VERSION:
		return _failure("unsupported_spatial_version")
	if target["universe_id"] != observer["universe_id"]:
		return _failure("different_universes")
	if not _point_valid(target, target_point_m) or not _point_valid(observer, observer_point_m):
		return _failure("invalid_or_outside_system_point")
	var tg: Dictionary = target["galaxy"]
	var og: Dictionary = observer["galaxy"]
	var ts: Dictionary = target["system"]
	var os: Dictionary = observer["system"]
	var delta: Array[float] = []
	var local_metres: Array[float] = []
	var domain: String
	if tg["galaxy_id"] == og["galaxy_id"]:
		if ts["system_id"] == os["system_id"]:
			domain = "system_metres"
			for i: int in range(3):
				local_metres.append(float(target_point_m[i]) - float(observer_point_m[i]))
				delta.append(local_metres[i] / LY_M)
		else:
			domain = "galaxy_lightyears"
			for i: int in range(3):
				var key: String = ["x", "y", "z"][i]
				# Both addresses already passed finite galaxy bounds. Safe int diff.
				var sectors: int = String(ts["sector_address"][key]).to_int() - String(os["sector_address"][key]).to_int()
				var d: float = float(sectors) * Catalog.SECTOR_WIDTH_LY
				d += (float(ts["offset_m"][i]) - float(os["offset_m"][i])) / LY_M
				d += (float(target_point_m[i]) - float(observer_point_m[i])) / LY_M
				delta.append(d)
		# Here delta is in shared galaxy axes; transform ONCE to universe axes.
		delta = Galaxies.rotate_local_ly(og, delta)
	else:
		domain = "intergalactic_lightyears"
		var tp: Array[float] = _system_center_ly(ts)
		var op: Array[float] = _system_center_ly(os)
		for i: int in range(3):
			tp[i] += float(target_point_m[i]) / LY_M
			op[i] += float(observer_point_m[i]) / LY_M
		tp = Galaxies.rotate_local_ly(tg, tp)
		op = Galaxies.rotate_local_ly(og, op)
		delta = Galaxies.relative_centres_ly(tg, og)
		for i: int in range(3):
			delta[i] += tp[i] - op[i]
	var distance: float = _length(delta)
	var direction: Array[float] = [0.0, 0.0, 0.0]
	if distance > 0.0:
		for i: int in range(3):
			direction[i] = delta[i] / distance
	var result: Dictionary = {
		"ok": true, "precision_domain": domain, "coincident": distance == 0.0,
		"delta_universe_ly": delta, "distance_ly": distance,
		"direction_universe": direction, "direction_observer_galaxy": _inverse_rotate(og, direction),
	}
	if domain == "system_metres":
		result["delta_system_m"] = local_metres
		result["distance_m"] = _length(local_metres)
	return result
