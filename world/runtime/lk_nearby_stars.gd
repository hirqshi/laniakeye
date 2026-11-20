class_name LkNearbyStars
extends RefCounted

const Spatial = preload("res://world/runtime/lk_universe_spatial.gd")
const Catalog = preload("res://world/generation/lk_world_catalog.gd")
const Identity = preload("res://world/generation/lk_world_identity.gd")
const VERSION: int = 1
const MAX_RADIUS_LY: float = 128.0
const MAX_PLANNED_SECTORS: int = 8192

var _definition
var _cache_limit: int
var _cache: Dictionary = {}
var _cache_fifo: Array[String] = []
var _cache_hits: int = 0
var _cache_misses: int = 0
var _sector_builds: int = 0
var _cache_evictions: int = 0

var _observer: Dictionary = {}
var _point: Array = []
var _radius: float = 0.0
var _plan: Array[Dictionary] = []
var _cursor: int = 0
var _sector_budget: int = 0
var _result_limit: int = 0
var _stars: Dictionary = {}
var _ordered: Array[Dictionary] = []
var _order_dirty: bool = true
var _order_builds: int = 0
var _finished: bool = true
var _cancelled: bool = false
var _error: String = "not_started"


# One query at a time per instance. Cache persists across begin() calls.
# Own a detached universe definition so cache contents cannot silently change.
func _init(definition, cache_limit_sectors: int = 256) -> void:
	_definition = definition.duplicate(true)
	_cache_limit = clampi(cache_limit_sectors, 1, 4096)


func cache_stats() -> Dictionary:
	return {"hits": _cache_hits, "misses": _cache_misses, "sector_builds": _sector_builds,
		"evictions": _cache_evictions, "resident_sectors": _cache.size()}


# Diagnostics are separate to preserve the sector-cache report schema.
func result_cache_stats() -> Dictionary:
	return {"order_builds": _order_builds, "dirty": _order_dirty, "ordered_stars": _ordered.size()}


func _get_sector(galaxy_index: int, x: int, y: int, z: int) -> Dictionary:
	var key: String = "%d/%d/%d/%d" % [galaxy_index, x, y, z]
	if _cache.has(key):
		_cache_hits += 1
		return _cache[key]
	_cache_misses += 1
	_sector_builds += 1
	var resolved: Dictionary = Spatial.resolve_sector(_definition, galaxy_index, x, y, z)
	if resolved["ok"]:
		if _cache.size() >= _cache_limit:
			var evicted: String = _cache_fifo.pop_front()
			_cache.erase(evicted)
			_cache_evictions += 1
		_cache[key] = resolved
		_cache_fifo.append(key)
	return resolved


static func _star_before(a: Dictionary, b: Dictionary) -> bool:
	if a["distance_ly"] == b["distance_ly"]:
		return String(a["star_id"]) < String(b["star_id"])
	return float(a["distance_ly"]) < float(b["distance_ly"])


# Observer must be an immutable, validated UniverseSpatial location.
# max_sectors limits TOTAL preparation, not work per frame.
func begin(observer: Dictionary, radius_ly: float, observer_point_m: Array = [0.0, 0.0, 0.0],
	max_sectors: int = 4096, max_results: int = 4096) -> Dictionary:
	_observer = {}
	_point = []
	_plan.clear()
	_stars.clear()
	_ordered.clear()
	_order_dirty = true
	_cursor = 0
	_radius = 0.0
	_sector_budget = 0
	_result_limit = 0
	_finished = true
	_cancelled = false
	_error = ""
	if _definition.catalog_version != 1 or not is_finite(radius_ly) or radius_ly < 0.0 or radius_ly > MAX_RADIUS_LY or max_sectors < 0 or max_sectors > MAX_PLANNED_SECTORS or max_results < 1 or max_results > 32768:
		_error = "invalid_query_parameters"
		return progress()
	if observer.get("universe_id", "") != _definition.get_universe_id():
		_error = "different_universe"
		return progress()
	var self_check: Dictionary = Spatial.relative(observer, observer, observer_point_m, observer_point_m)
	if not self_check["ok"]:
		_error = self_check["code"]
		return progress()
	_observer = observer.duplicate(true)
	_point = observer_point_m.duplicate()
	_radius = radius_ly
	_sector_budget = max_sectors
	_result_limit = max_results
	var placement: Dictionary = _observer["system"]
	var base: Array[int] = []
	var offset: Array[float] = []
	var lower: Array[int] = []
	var upper: Array[int] = []
	var box_count: int = 1
	for axis: int in range(3):
		var key: String = ["x", "y", "z"][axis]
		base.append(String(placement["sector_address"][key]).to_int())
		offset.append(float(placement["offset_m"][axis]) / Spatial.LY_M + float(_point[axis]) / Spatial.LY_M)
		lower.append(int(floor((offset[axis] - radius_ly) / Catalog.SECTOR_WIDTH_LY)))
		upper.append(int(floor((offset[axis] + radius_ly) / Catalog.SECTOR_WIDTH_LY)))
		box_count *= upper[axis] - lower[axis] + 1
	if box_count > MAX_PLANNED_SECTORS:
		_error = "planning_budget_exceeded"
		return progress()
	for dx: int in range(lower[0], upper[0] + 1):
		for dy: int in range(lower[1], upper[1] + 1):
			for dz: int in range(lower[2], upper[2] + 1):
				var shifts: Array[int] = [dx, dy, dz]
				var nearest_squared: float = 0.0
				for axis: int in range(3):
					var lo: float = float(shifts[axis]) * Catalog.SECTOR_WIDTH_LY - offset[axis]
					var hi: float = lo + Catalog.SECTOR_WIDTH_LY
					var nearest: float = lo if lo > 0.0 else (hi if hi < 0.0 else 0.0)
					nearest_squared += nearest * nearest
				if nearest_squared > radius_ly * radius_ly:
					continue
				var x: int = base[0] + dx
				var y: int = base[1] + dy
				var z: int = base[2] + dz
				if Spatial.sector_may_intersect(_observer["galaxy"], x, y, z):
					_plan.append({"x": x, "y": y, "z": z, "min_squared": nearest_squared})
	_plan.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["min_squared"] != b["min_squared"]:
			return float(a["min_squared"]) < float(b["min_squared"])
		for key: String in ["x", "y", "z"]:
			if a[key] != b[key]:
				return int(a[key]) < int(b[key])
		return false
	)
	_finished = _plan.is_empty() or _sector_budget == 0
	return progress()


# Synchronous bounded number of sector preparations; NOT a millisecond deadline.
# A cold sector can still be expensive. Caller chooses when to call this.
func step(sectors_this_step: int = 1) -> Dictionary:
	if _finished or not _error.is_empty():
		return progress()
	if sectors_this_step < 1:
		return {"ok": false, "code": "invalid_step_budget"}
	var stop: int = mini(mini(_cursor + sectors_this_step, _sector_budget), _plan.size())
	var galaxy_index: int = String(_observer["galaxy"]["galaxy_index"]).to_int()
	while _cursor < stop:
		var address: Dictionary = _plan[_cursor]
		var sector: Dictionary = _get_sector(galaxy_index, address["x"], address["y"], address["z"])
		if not sector["ok"]:
			_error = sector["code"]
			_finished = true
			return progress()
		for location: Dictionary in sector["locations"]:
			var system_id: String = location["system"]["system_id"]
			if system_id == _observer["system"]["system_id"]:
				continue
			var relative: Dictionary = Spatial.relative(location, _observer, [0.0, 0.0, 0.0], _point)
			if not relative["ok"]:
				_error = relative["code"]
				_finished = true
				return progress()
			if float(relative["distance_ly"]) <= _radius:
				var star_id: String = Identity.child_id(system_id, "star", "0")
				_order_dirty = true
				_stars[star_id] = {"star_id": star_id, "system_id": system_id,
					"location": location, "distance_ly": relative["distance_ly"],
					"direction_galaxy": relative["direction_observer_galaxy"],
					"direction_universe": relative["direction_universe"]}
		_cursor += 1
	_finished = _cursor >= _plan.size() or _cursor >= _sector_budget
	return progress()


func cancel() -> void:
	_cancelled = true
	_finished = true


func progress() -> Dictionary:
	var search_complete: bool = _error.is_empty() and not _cancelled and _cursor == _plan.size()
	var result_truncated: bool = _stars.size() > _result_limit
	return {"ok": _error.is_empty(), "code": _error,
		"finished": _finished, "search_complete": search_complete,
		"complete": search_complete and not result_truncated,
		"cancelled": _cancelled, "result_truncated": result_truncated,
		"sector_budget_exhausted": _error.is_empty() and not _cancelled and _cursor < _plan.size() and _cursor >= _sector_budget,
		"planned_sectors": _plan.size(), "scanned_sectors": _cursor,
		"matched_stars": _stars.size()}


# Reuse ordering, but detach exported records on every call. Progress and sector
# statistics remain live; use progress() when only counters are needed.
func result() -> Dictionary:
	var report: Dictionary = progress()
	if _order_dirty:
		_ordered.clear()
		for star: Dictionary in _stars.values():
			_ordered.append(star)
		_ordered.sort_custom(_star_before)
		_order_dirty = false
		_order_builds += 1
	var stars: Array[Dictionary] = []
	for i: int in range(mini(_ordered.size(), _result_limit)):
		stars.append(_ordered[i].duplicate(true))
	report["stars"] = stars
	report["query_radius_ly"] = _radius
	report["cache"] = cache_stats()
	return report


# Reprojects ONLY supplied candidates: no sector lookups, body generation or
# coverage expansion. New system/radius/large movement requires another query.
static func reproject(stars: Array, observer: Dictionary, observer_point_m: Array = [0.0, 0.0, 0.0]) -> Dictionary:
	var projected: Array[Dictionary] = []
	var self_check: Dictionary = Spatial.relative(observer, observer, observer_point_m, observer_point_m)
	if not self_check["ok"]:
		return self_check
	for star: Dictionary in stars:
		if star["system_id"] == observer["system"]["system_id"]:
			continue
		var relative: Dictionary = Spatial.relative(star["location"], observer, [0.0, 0.0, 0.0], observer_point_m)
		if not relative["ok"]:
			return relative
		var entry: Dictionary = star.duplicate(false)
		entry["distance_ly"] = relative["distance_ly"]
		entry["direction_galaxy"] = relative["direction_observer_galaxy"]
		entry["direction_universe"] = relative["direction_universe"]
		projected.append(entry)
	projected.sort_custom(_star_before)
	return {"ok": true, "stars": projected, "coverage_expanded": false}
