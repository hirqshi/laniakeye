extends SceneTree

const Spatial = preload("res://world/runtime/lk_universe_spatial.gd")
const Definition = preload("res://world/generation/lk_universe_definition.gd")
const Catalog = preload("res://world/generation/lk_world_catalog.gd")
const Bodies = preload("res://world/generation/lk_body_catalog.gd")
const Orbits = preload("res://world/generation/lk_safe_orbit_layout.gd")
var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("SpatialLayoutCache: FAIL " + label)


func _initialize() -> void:
	var definition = Definition.new()
	var catalog = Catalog.new(definition.get_universe_id(), 1)
	var source: Dictionary = catalog.describe_system(0, 0, 0, 0, 0)
	var reference: Dictionary = Orbits.build(Bodies.build(source))
	Spatial.clear_layout_cache()
	_check(Spatial._layout_for(source) == reference, "cold layout parity")
	_check(Spatial._layout_for(source) == reference, "warm layout parity")
	_check(Spatial.layout_cache_stats()["builds"] == 1 and Spatial.layout_cache_stats()["hits"] == 1, "one build then hit")
	var changed: Dictionary = Spatial._layout_for(source)
	changed["star"]["radius_m"] = -1.0
	changed["planets"].clear()
	_check(Spatial._layout_for(source) == reference, "returned layout isolation")
	var edited_source: Dictionary = source.duplicate(true)
	edited_source["cache_test_marker"] = true
	var builds: int = Spatial.layout_cache_stats()["builds"]
	_check(Spatial._layout_for(edited_source) == reference, "changed descriptor parity")
	_check(Spatial.layout_cache_stats()["builds"] == builds + 1, "same ID changed descriptor rebuilds")
	edited_source["cache_test_marker"] = false
	builds = Spatial.layout_cache_stats()["builds"]
	Spatial._layout_for(edited_source)
	_check(Spatial.layout_cache_stats()["builds"] == builds + 1, "cached source detached")
	Spatial.clear_layout_cache()
	var cold: Dictionary = Spatial.resolve_system(definition, 0, 0, 0, 0, 0)
	var warm: Dictionary = Spatial.resolve_system(definition, 0, 0, 0, 0, 0)
	_check(cold.get("ok", false) and cold == warm, "location parity")
	_check(Spatial.layout_cache_stats()["builds"] == 1 and Spatial.layout_cache_stats()["hits"] == 1, "resolve uses cache")
	if warm.get("ok", false):
		warm["location"]["system"]["offset_m"][0] = -123.0
		_check(Spatial.resolve_system(definition, 0, 0, 0, 0, 0) == cold, "location isolation")
	Spatial.resolve_sector(definition, 0, 0, 0, 0)
	_check(Spatial.layout_cache_stats()["builds"] == 1, "sector and system share cache")
	builds = Spatial.layout_cache_stats()["builds"]
	_check(Spatial.resolve_system(definition, 0, 9223372036854775807, 0, 0, 0)["code"] == "outside_galaxy", "huge address rejected")
	_check(Spatial.layout_cache_stats()["builds"] == builds, "outside guard precedes build")
	var other = Definition.new()
	other.universe_seed = "spatial-layout-cache-other"
	var other_catalog = Catalog.new(other.get_universe_id(), 1)
	for x: int in range(32):
		var sector: Dictionary = other_catalog.describe_sector(0, x, 0, 0)
		for item: Dictionary in sector["systems"]:
			Spatial._layout_for(item)
	_check(Spatial.layout_cache_stats()["resident"] == Spatial.LAYOUT_CACHE_CAPACITY, "bounded across universes")
	builds = Spatial.layout_cache_stats()["builds"]
	_check(Spatial._layout_for(source) == reference, "parity after eviction")
	_check(Spatial.layout_cache_stats()["builds"] == builds + 1, "old layout evicted")
	Spatial.clear_layout_cache()
	_check(Spatial.layout_cache_stats() == {"resident": 0, "builds": 0, "hits": 0}, "clear resets storage and counters")
	if _failures == 0:
		print("SpatialLayoutCache: PASS cold/warm parity, descriptor keys, isolation, shared queries, bounds, eviction")
	quit(0 if _failures == 0 else 1)
