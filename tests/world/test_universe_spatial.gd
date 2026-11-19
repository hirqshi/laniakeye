extends SceneTree

const Spatial = preload("res://world/runtime/lk_universe_spatial.gd")
const Definition = preload("res://world/generation/lk_universe_definition.gd")
const Catalog = preload("res://world/generation/lk_world_catalog.gd")
const Galaxies = preload("res://world/generation/lk_galaxy_placement.gd")
const GalaxyValidator = preload("res://world/generation/lk_galaxy_placement_validator.gd")

var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("UniverseSpatial: FAIL " + label)


func _length(a: Array) -> float:
	return sqrt(float(a[0]) * float(a[0]) + float(a[1]) * float(a[1]) + float(a[2]) * float(a[2]))


func _initialize() -> void:
	var definition = Definition.new()
	var root: String = definition.get_universe_id()
	var catalog = Catalog.new(root, 1)
	var locations: Array[Dictionary] = []
	for x: int in range(-1, 2):
		for y: int in range(-1, 2):
			for z: int in range(-1, 2):
				var sector: Dictionary = Spatial.resolve_sector(definition, 0, x, y, z)
				_check(sector["ok"], "sector resolves")
				if not sector["ok"]:
					continue
				_check(sector["filtered"] == 0, "central sectors entirely admitted")
				for location: Dictionary in sector["locations"]:
					_check(location["system"]["galaxy_id"] == catalog.galaxy_id(0), "galaxy identity preserved")
					locations.append(location)
	_check(locations.size() >= 2, "nearby system sample")
	if locations.size() < 2:
		quit(1)
		return
	var home_result: Dictionary = Spatial.resolve_system(definition, 0, 0, 0, 0, 0)
	_check(home_result["ok"], "existing home system admitted")
	if not home_result["ok"]:
		quit(1)
		return
	var home: Dictionary = home_result["location"]
	var single: Dictionary = Spatial.relative(home, home, [1.0, 0.0, 0.0])
	_check(single["ok"] and single["precision_domain"] == "system_metres", "same-system precision branch")
	_check(single["delta_system_m"] == [1.0, 0.0, 0.0] and single["distance_m"] == 1.0, "one metre not lost in galaxy coordinates")
	var coincident: Dictionary = Spatial.relative(home, home)
	_check(coincident["coincident"] and coincident["direction_universe"] == [0.0, 0.0, 0.0], "coincident direction explicitly zero")
	_check(not Spatial.relative(home, home, [NAN, 0.0, 0.0])["ok"], "reject nonfinite point")
	_check(not Spatial.relative(home, home, [float(home["system"]["system_bound_m"]) * 2.0, 0.0, 0.0])["ok"], "reject point outside system bound")
	# Controlled orthonormal orientation fixture, not a change to generated data.
	var turned: Dictionary = home.duplicate(true)
	turned["galaxy"]["galaxy_to_universe_axes"] = [[0.0, 0.0, -1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0]]
	_check(GalaxyValidator.validate(turned["galaxy"], root).is_empty(), "controlled orientation geometrically valid")
	var yawed: Dictionary = Spatial.relative(turned, turned, [1.0, 0.0, 0.0])
	_check(yawed["direction_universe"] == [0.0, 0.0, -1.0], "known quarter-turn maps local X to universe -Z")
	_check(yawed["direction_observer_galaxy"] == [1.0, 0.0, 0.0], "inverse transform maps direction back")
	var pair_checks: int = 0
	for location: Dictionary in locations:
		var outward: Dictionary = Spatial.relative(location, home)
		var inward: Dictionary = Spatial.relative(home, location)
		_check(outward["ok"] and inward["ok"], "relative query")
		for axis: int in range(3):
			_check(absf(float(outward["delta_universe_ly"][axis]) + float(inward["delta_universe_ly"][axis])) < 1.0e-10, "same-galaxy antisymmetry")
		if not outward["coincident"]:
			_check(absf(_length(outward["direction_universe"]) - 1.0) < 1.0e-12, "unit universe direction")
			_check(absf(_length(outward["direction_observer_galaxy"]) - 1.0) < 1.0e-12, "unit observer-galaxy direction")
		pair_checks += 1
	# Test bounds before any huge address arithmetic / expensive body generation.
	var outside: Dictionary = Spatial.resolve_sector(definition, 0, 9223372036854775807, 0, 0)
	_check(outside["ok"] and outside["outside_galaxy"] and outside["locations"].is_empty(), "huge sector safely outside")
	_check(Spatial.resolve_system(definition, 0, -9223372036854775807, 0, 0, 0)["code"] == "outside_galaxy", "negative huge sector safely rejected")
	var galaxy: Dictionary = home["galaxy"]
	var edge_x: int = int(floor(float(galaxy["envelope_radius_ly"]) / Catalog.SECTOR_WIDTH_LY))
	var boundary_checked: int = 0
	for x: int in range(edge_x - 2, edge_x + 3):
		var sector: Dictionary = Spatial.resolve_sector(definition, 0, x, 0, 0)
		_check(sector["ok"], "boundary sector query")
		if not sector["ok"]:
			continue
		_check(sector["locations"].size() + int(sector["filtered"]) == int(sector["source_count"]), "boundary accounting")
		for location: Dictionary in sector["locations"]:
			var placement: Dictionary = location["system"]
			var p: Array = [float(x) * Catalog.SECTOR_WIDTH_LY + float(placement["offset_m"][0]) / Spatial.LY_M, float(placement["offset_m"][1]) / Spatial.LY_M, float(placement["offset_m"][2]) / Spatial.LY_M]
			_check(_length(p) + float(placement["system_bound_m"]) / Spatial.LY_M <= float(galaxy["envelope_radius_ly"]), "independent galaxy containment")
		boundary_checked += 1
	var cross_locations: Array[Dictionary] = [home]
	for index: int in [1, 2]:
		var found: Dictionary = {}
		for x: int in range(-1, 2):
			var sector: Dictionary = Spatial.resolve_sector(definition, index, x, 0, 0)
			if sector["ok"] and not sector["locations"].is_empty():
				found = sector["locations"][0]
				break
		_check(not found.is_empty(), "other galaxy system")
		if not found.is_empty():
			cross_locations.append(found)
	if cross_locations.size() == 3:
		var ab: Dictionary = Spatial.relative(cross_locations[1], cross_locations[0])
		var ba: Dictionary = Spatial.relative(cross_locations[0], cross_locations[1])
		var bc: Dictionary = Spatial.relative(cross_locations[2], cross_locations[1])
		var ac: Dictionary = Spatial.relative(cross_locations[2], cross_locations[0])
		_check(ab["precision_domain"] == "intergalactic_lightyears", "cross-galaxy branch")
		for axis: int in range(3):
			_check(absf(float(ab["delta_universe_ly"][axis]) + float(ba["delta_universe_ly"][axis])) < 1.0e-7, "cross-galaxy antisymmetry")
			_check(absf(float(ab["delta_universe_ly"][axis]) + float(bc["delta_universe_ly"][axis]) - float(ac["delta_universe_ly"][axis])) < 1.0e-7, "transform composition triangle")
		_check(absf(_length(ab["direction_observer_galaxy"]) - 1.0) < 1.0e-12, "cross-galaxy direction expressed in observer axes")
		print("UniverseSpatial: galaxy_0_to_1=%.3f ly" % ab["distance_ly"])
	# Resolve in reverse order using IDs/addresses; no shared mutable placement state.
	for i: int in range(locations.size() - 1, -1, -1):
		var p: Dictionary = locations[i]["system"]
		var a: Dictionary = p["sector_address"]
		var repeated: Dictionary = Spatial.resolve_system(definition, 0, String(a["x"]).to_int(), String(a["y"]).to_int(), String(a["z"]).to_int(), p["slot"])
		_check(repeated["ok"] and repeated["location"] == locations[i], "reverse request order")
	print("UniverseSpatial: local_systems=%d relative_checks=%d boundary_queries=%d" % [locations.size(), pair_checks, boundary_checked])
	if _failures == 0:
		print("UniverseSpatial: PASS finite admission, identities, metre branch, galaxy axes, cross-galaxy composition, int64 guard, determinism")
	quit(0 if _failures == 0 else 1)
