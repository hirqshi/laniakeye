extends SceneTree

const Audit = preload("res://game/world/generation/lk_population_audit.gd")
const Photo = preload("res://game/world/generation/lk_stellar_photometry.gd")
const Definition = preload("res://game/world/generation/lk_universe_definition.gd")
const Catalog = preload("res://game/world/generation/lk_world_catalog.gd")
const Bodies = preload("res://game/world/generation/lk_body_catalog.gd")
const Galaxies = preload("res://game/world/generation/lk_galaxy_placement.gd")
const Spatial = preload("res://game/world/runtime/lk_universe_spatial.gd")
const Nearby = preload("res://game/world/runtime/lk_nearby_stars.gd")

var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("StellarPopulation: FAIL " + label)


func _initialize() -> void:
	var definition = Definition.new()
	var root: String = definition.get_universe_id()
	var catalog = Catalog.new(root, 1)
	var system_count: int = 0
	var planet_count: int = 0
	for x: int in range(-2, 3):
		for y: int in range(-2, 3):
			for z: int in range(-2, 3):
				var cheap: Dictionary = Audit.sector_header(root, 0, x, y, z)
				var source: Dictionary = catalog.describe_sector(0, x, y, z)
				_check(cheap["sector_id"] == source["id"], "sector identity")
				_check(cheap["systems"].size() == source["systems"].size(), "cheap system count matches catalogue")
				var planets: int = 0
				for i: int in range(source["systems"].size()):
					var s: Dictionary = source["systems"][i]
					_check(cheap["systems"][i]["system_id"] == s["id"], "system ID")
					_check(cheap["systems"][i]["star_id"] == s["stars"][0]["id"], "star ID")
					_check(cheap["systems"][i]["planet_count"] == s["planets"].size(), "exact cheap planet count")
					planets += s["planets"].size()
				_check(cheap["planet_count"] == planets, "sector planet total")
				system_count += source["systems"].size()
				planet_count += planets
	var source: Dictionary = catalog.describe_system(0, 0, 0, 0, 0)
	var physical: Dictionary = Bodies.build(source)
	var actual_star: Dictionary = physical["stars"][0]
	var photo: Dictionary = Photo.describe_star(actual_star["id"])
	_check(photo["mass_kg"] == actual_star["mass_kg"], "photometry does not change stellar mass")
	_check(photo["radius_m"] == actual_star["radius_m"], "photometry does not change stellar radius")
	var solar_absolute: float = Photo.SOLAR_MAGNITUDE_PROXY
	_check(absf(Photo.apparent_magnitude(solar_absolute, 10.0 * Photo.PARSEC_LY) - solar_absolute) < 1.0e-12, "10pc magnitude normalization")
	var a: float = Photo.apparent_magnitude(solar_absolute, 10.0)
	var b: float = Photo.apparent_magnitude(solar_absolute, 100.0)
	_check(absf(b - a - 5.0) < 1.0e-12, "10x distance gives +5 magnitudes")
	var near: Dictionary = Photo.observe(photo, 10.0)
	var far: Dictionary = Photo.observe(photo, 100.0)
	_check(absf(float(near["relative_flux"]) / float(far["relative_flux"]) - 100.0) < 1.0e-9, "inverse-square flux")
	_check(not Photo.observe(photo, 0.0)["ok"], "reject zero photometric distance")
	var located: Dictionary = Spatial.resolve_system(definition, 0, 0, 0, 0, 0)
	_check(located["ok"], "observer location")
	if not located["ok"]:
		quit(1)
		return
	var observer: Dictionary = located["location"]
	var query = Nearby.new(definition, 64)
	query.begin(observer, 16.0)
	while not query.progress()["finished"]:
		query.step(4)
	var exact: Dictionary = query.result()
	_check(exact["complete"], "exact reference complete")
	var visible_exact: int = 0
	for star: Dictionary in exact["stars"]:
		if Photo.observe(Photo.describe_star(star["star_id"]), star["distance_ly"], 6.0)["passes_limit"]:
			visible_exact += 1
	var bounds: Dictionary = Audit.coverage(observer, 16.0, 6.0)
	_check(bounds["spatial_lower"] <= exact["stars"].size() and exact["stars"].size() <= bounds["spatial_upper"], "exact spatial result enclosed by cheap bounds")
	_check(bounds["photometric_lower"] <= visible_exact and visible_exact <= bounds["photometric_upper"], "exact photometric result enclosed by bounds")
	for radius: float in [32.0, 64.0, 128.0]:
		var started: int = Time.get_ticks_usec()
		var report: Dictionary = Audit.coverage(observer, radius, 6.0)
		_check(report["ok"], "coverage report")
		_check(report["spatial_lower"] <= report["spatial_upper"] and report["photometric_lower"] <= report["photometric_upper"], "ordered coverage bounds")
		_check(report["photometric_lower"] <= report["spatial_lower"] and report["photometric_upper"] <= report["spatial_upper"], "visible subset of spatial candidates")
		print("StellarPopulation: R=%.0f ly candidates=%d..%d magnitude6_proxy=%d..%d sectors=%d audit_ms=%.2f" % [
			radius, report["spatial_lower"], report["spatial_upper"], report["photometric_lower"], report["photometric_upper"], report["queried_sectors"], float(Time.get_ticks_usec() - started) / 1000.0,
		])
	var home: Dictionary = Audit.expected_population(observer["galaxy"]["envelope_radius_ly"])
	var total: Dictionary = Audit.universe_expectation()
	_check(absf(float(home["expected_planets"]) / float(home["expected_systems"]) - 4.4) < 1.0e-12, "4.4 planets per system expectation")
	_check(absf(float(Audit.expected_population(2000.0)["expected_planets"]) / float(Audit.expected_population(1000.0)["expected_planets"]) - 8.0) < 1.0e-12, "population scales with volume")
	_check(total["galaxy_capacity_exact"] == "9223372036854775808", "exact galaxy address capacity string")
	print("StellarPopulation: sampled_systems=%d sampled_planets=%d" % [system_count, planet_count])
	print("StellarPopulation: EXPECTATION home_planets=%.6f trillion mean_galaxy_planets=%.6f trillion addressable_universe_planets=%.6f x10^31 (not enumerated)" % [
		float(home["expected_planets"]) / 1.0e12, float(total["expected_planets_per_galaxy"]) / 1.0e12, float(total["expected_planets_addressable_universe"]) / 1.0e31,
	])
	if _failures == 0:
		print("StellarPopulation: PASS catalogue census, mass/radius parity, photometry, coverage bounds, population expectations")
	quit(0 if _failures == 0 else 1)
