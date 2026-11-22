extends SceneTree

const Nearby = preload("res://game/world/runtime/lk_nearby_stars.gd")
const Spatial = preload("res://game/world/runtime/lk_universe_spatial.gd")
const Definition = preload("res://game/world/generation/lk_universe_definition.gd")
var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("NearbyResultCache: FAIL " + label)


func _before(a: Dictionary, b: Dictionary) -> bool:
	if a["distance_ly"] == b["distance_ly"]:
		return String(a["star_id"]) < String(b["star_id"])
	return float(a["distance_ly"]) < float(b["distance_ly"])


func _verify(query) -> Dictionary:
	var ordered: Array[Dictionary] = []
	for star: Dictionary in query._stars.values():
		ordered.append(star.duplicate(true))
	ordered.sort_custom(_before)
	var expected: Array[Dictionary] = []
	for i: int in range(mini(ordered.size(), query._result_limit)):
		expected.append(ordered[i])
	var stats: Dictionary = query.result_cache_stats()
	var first: Dictionary = query.result()
	_check(first["stars"] == expected, "fresh sort parity")
	var builds: int = query.result_cache_stats()["order_builds"]
	_check(builds == int(stats["order_builds"]) + (1 if stats["dirty"] else 0), "rebuild only when dirty")
	_check(query.result() == first, "repeat report parity")
	_check(query.result_cache_stats()["order_builds"] == builds, "repeat skips sorting")
	return first


func _finish(query) -> Dictionary:
	var steps: int = 0
	while not query.progress()["finished"] and steps <= Nearby.MAX_PLANNED_SECTORS:
		query.step(1)
		_verify(query)
		steps += 1
	_check(query.progress()["finished"], "bounded termination")
	return _verify(query)


func _initialize() -> void:
	var definition = Definition.new()
	var located: Dictionary = Spatial.resolve_system(definition, 0, 0, 0, 0, 0)
	_check(located.get("ok", false), "home location")
	if not located.get("ok", false):
		quit(1)
		return
	var home: Dictionary = located["location"]
	var query = Nearby.new(definition)
	_verify(query)
	query.begin(home, 16.0)
	_check(_verify(query)["stars"].is_empty(), "begin clears prior ordering")
	_check(not query.step(0)["ok"], "invalid step rejected")
	_verify(query)
	var full: Dictionary = _finish(query)
	_check(full["complete"] and full["stars"].size() > 1, "full sample")
	var exported: Dictionary = query.result()
	if not exported["stars"].is_empty():
		exported["stars"][0]["location"]["system"]["offset_m"][0] = -999.0
		exported["stars"][0]["direction_galaxy"][0] = -999.0
		exported["stars"].clear()
	_check(query.result()["stars"] == full["stars"], "deep export isolation")
	var builds: int = query.result_cache_stats()["order_builds"]
	var hits: int = query.cache_stats()["hits"]
	query._get_sector(0, 0, 0, 0)
	_check(query.result()["cache"]["hits"] == hits + 1, "sector statistics stay live")
	_check(query.result_cache_stats()["order_builds"] == builds, "metadata does not re-sort")
	query.cancel()
	var cancelled: Dictionary = query.result()
	_check(cancelled["cancelled"] and not cancelled["complete"], "cancel status stays live")
	_check(cancelled["stars"] == full["stars"] and query.result_cache_stats()["order_builds"] == builds, "cancel retains ordering")
	query.begin(home, 16.0, [0.0, 0.0, 0.0], 4096, 1)
	var limited: Dictionary = _finish(query)
	_check(limited["result_truncated"] and limited["stars"].size() == 1, "changed limit")
	_check(limited["stars"][0] == full["stars"][0], "nearest retained")
	query.begin(home, 0.0)
	var empty: Dictionary = _finish(query)
	_check(empty["complete"] and empty["stars"].is_empty() and empty["query_radius_ly"] == 0.0, "zero radius reset")
	query.begin(home, 16.0, [0.0, 0.0, 0.0], 0)
	_check(_verify(query)["sector_budget_exhausted"], "zero budget")
	query.begin(home, NAN)
	var invalid: Dictionary = _verify(query)
	_check(not invalid["ok"] and invalid["stars"].is_empty(), "invalid begin clears results")
	# Controlled equal-distance fixture checks the stable ID tie-break.
	query.begin(home, 16.0)
	query._stars["b"] = {"star_id": "b", "distance_ly": 1.0}
	query._stars["a"] = {"star_id": "a", "distance_ly": 1.0}
	_check(_verify(query)["stars"][0]["star_id"] == "a", "ID tie-break")
	if _failures == 0:
		print("NearbyResultCache: PASS partial parity, sort reuse, deep isolation, live metadata, cancel, reset, limits, ties")
	quit(0 if _failures == 0 else 1)
