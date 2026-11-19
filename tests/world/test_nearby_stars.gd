extends SceneTree

const Nearby = preload("res://world/runtime/lk_nearby_stars.gd")
const Spatial = preload("res://world/runtime/lk_universe_spatial.gd")
const Definition = preload("res://world/generation/lk_universe_definition.gd")
const Identity = preload("res://world/generation/lk_world_identity.gd")

var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("NearbyStars: FAIL " + label)


func _finish(query, chunk: int) -> Dictionary:
	var calls: int = 0
	while not query.progress()["finished"]:
		query.step(chunk)
		calls += 1
		if calls > Nearby.MAX_PLANNED_SECTORS + 1:
			_check(false, "query termination")
			break
	return query.result()


func _ids(stars: Array) -> Array[String]:
	var ids: Array[String] = []
	for star: Dictionary in stars:
		ids.append(star["star_id"])
	return ids


func _initialize() -> void:
	var definition = Definition.new()
	var located: Dictionary = Spatial.resolve_system(definition, 0, 0, 0, 0, 0)
	_check(located["ok"], "home location")
	if not located["ok"]:
		quit(1)
		return
	var home: Dictionary = located["location"]
	var query = Nearby.new(definition, 256)
	var started: Dictionary = query.begin(home, 16.0)
	_check(started["ok"] and not started["complete"], "query starts pending")
	var full: Dictionary = _finish(query, 1)
	_check(full["ok"] and full["complete"] and full["search_complete"], "full query completes")
	_check(full["stars"].size() > 1, "nonempty neighboring stars")
	var seen: Dictionary = {}
	var last_distance: float = -1.0
	for star: Dictionary in full["stars"]:
		_check(not seen.has(star["star_id"]), "no duplicate stars")
		seen[star["star_id"]] = true
		_check(star["system_id"] != home["system"]["system_id"], "exclude current system")
		_check(float(star["distance_ly"]) <= 16.0 and float(star["distance_ly"]) >= last_distance, "radius and sorted distances")
		last_distance = star["distance_ly"]
		_check(star["star_id"] == Identity.child_id(star["system_id"], "star", "0"), "canonical star ID")
		var dir: Array = star["direction_galaxy"]
		_check(absf(float(dir[0]) * float(dir[0]) + float(dir[1]) * float(dir[1]) + float(dir[2]) * float(dir[2]) - 1.0) < 1.0e-12, "unit galaxy direction")

	# Brute-force all 27 surrounding sectors, NOT the query's planned sectors.
	# With observer in sector (0,0,0) and radius 16ly, this is a complete reference.
	var expected: Array[Dictionary] = []
	for x: int in range(-1, 2):
		for y: int in range(-1, 2):
			for z: int in range(-1, 2):
				var sector: Dictionary = Spatial.resolve_sector(definition, 0, x, y, z)
				_check(sector["ok"], "reference sector")
				if not sector["ok"]:
					continue
				for location: Dictionary in sector["locations"]:
					if location["system"]["system_id"] == home["system"]["system_id"]:
						continue
					var relative: Dictionary = Spatial.relative(location, home)
					if float(relative["distance_ly"]) <= 16.0:
						expected.append({"star_id": Identity.child_id(location["system"]["system_id"], "star", "0"), "distance_ly": relative["distance_ly"]})
	expected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["distance_ly"] == b["distance_ly"]:
			return String(a["star_id"]) < String(b["star_id"])
		return float(a["distance_ly"]) < float(b["distance_ly"])
	)
	_check(_ids(full["stars"]) == _ids(expected), "complete radius search matches brute-force reference")
	var builds: int = query.cache_stats()["sector_builds"]
	query.begin(home, 16.0)
	var warm: Dictionary = _finish(query, 7)
	_check(warm["stars"] == full["stars"], "chunk size and warm cache do not change results")
	_check(query.cache_stats()["sector_builds"] == builds, "warm search does not regenerate sectors")
	var projection: Dictionary = Nearby.reproject(full["stars"], home, [1.0, 0.0, 0.0])
	_check(projection["ok"] and not projection["coverage_expanded"], "cheap reprojection")
	_check(query.cache_stats()["sector_builds"] == builds, "reprojection does not generate bodies")
	if projection["ok"]:
		for star: Dictionary in projection["stars"]:
			var reference: Dictionary = Spatial.relative(star["location"], home, [0.0, 0.0, 0.0], [1.0, 0.0, 0.0])
			_check(star["distance_ly"] == reference["distance_ly"], "reprojection matches direct geometry")
	# Exported result must not give mutable access to cached locations.
	var exported: Dictionary = query.result()
	if not exported["stars"].is_empty():
		exported["stars"][0]["location"]["system"]["offset_m"][0] = -999.0
	query.begin(home, 16.0)
	_check(_finish(query, 4)["stars"] == full["stars"], "result mutation cannot corrupt cache")
	query.begin(home, 16.0, [0.0, 0.0, 0.0], 4096, 1)
	var limited: Dictionary = _finish(query, 5)
	_check(limited["search_complete"] and not limited["complete"] and limited["result_truncated"], "result cap explicitly incomplete")
	_check(limited["stars"].size() == 1 and limited["stars"][0]["star_id"] == full["stars"][0]["star_id"], "result cap keeps nearest known star")
	query.begin(home, 16.0, [0.0, 0.0, 0.0], 0)
	var zero_budget: Dictionary = query.result()
	_check(zero_budget["finished"] and not zero_budget["complete"] and zero_budget["sector_budget_exhausted"], "zero preparation budget reported")
	query.begin(home, 16.0, [0.0, 0.0, 0.0], 1)
	var partial: Dictionary = _finish(query, 8)
	_check(partial["scanned_sectors"] == 1 and not partial["search_complete"], "sector cap respected")
	query.begin(home, 0.0)
	var empty: Dictionary = _finish(query, 1)
	_check(empty["complete"] and empty["stars"].is_empty(), "zero radius excludes local star")
	query.begin(home, 16.0)
	query.cancel()
	_check(query.progress()["cancelled"] and not query.progress()["complete"], "cancel reported")
	_check(not query.begin(home, NAN)["ok"], "reject nonfinite radius")
	_check(not query.begin(home, Nearby.MAX_RADIUS_LY + 1.0)["ok"], "reject oversized radius")
	var tiny_cache = Nearby.new(definition, 2)
	tiny_cache.begin(home, 16.0)
	var evicted: Dictionary = _finish(tiny_cache, 3)
	_check(evicted["stars"] == full["stars"] and tiny_cache.cache_stats()["resident_sectors"] <= 2, "cache eviction does not change result")
	print("NearbyStars: radius=16 ly stars=%d sectors=%d warm_builds_added=%d" % [full["stars"].size(), full["scanned_sectors"], int(warm["cache"]["sector_builds"]) - builds])
	if _failures == 0:
		print("NearbyStars: PASS radius reference, IDs, exclusion, ordering, incremental budgets, cache, reprojection, truncation")
	quit(0 if _failures == 0 else 1)
