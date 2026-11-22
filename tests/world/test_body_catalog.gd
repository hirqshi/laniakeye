extends SceneTree

const Identity = preload("res://game/world/generation/lk_world_identity.gd")
const Catalog = preload("res://game/world/generation/lk_world_catalog.gd")
const Bodies = preload("res://game/world/generation/lk_body_catalog.gd")

var _failures: int = 0
var _seen: Dictionary = {}
var _systems: int = 0
var _planets: int = 0
var _moons: int = 0
var _largest_parent: Dictionary = {}
var _small_bodies: int = 0
var _gas_giants: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("BodyCatalog: FAIL " + label)


func _check_physical(body: Dictionary) -> void:
	var id: String = body["id"]
	_check(Identity.is_valid_id(id) and not _seen.has(id), "unique valid ID")
	_seen[id] = true
	var radius: float = body["radius_m"]
	var mass: float = body["mass_kg"]
	_check(is_finite(radius) and radius > 0.0, "finite positive radius")
	_check(is_finite(mass) and mass > 0.0, "finite positive mass")
	_check(float(body["physical_bound_radius_m"]) >= radius, "physical bound")
	_check(absf(float(body["mu_m3_s2"]) - Bodies.G_SI * mass) / (Bodies.G_SI * mass) < 1.0e-12,
		"mass and mu consistency")
	if body["kind"] != "star":
		var expected: float = Bodies.sphere_mass(radius, body["density_kg_m3"])
		_check(absf(mass - expected) / expected < 1.0e-12, "density and mass consistency")


func _check_moons(parent: Dictionary, moons: Array) -> void:
	var total: float = 0.0
	for moon: Dictionary in moons:
		_check_physical(moon)
		_check(moon["parent_id"] == parent["id"], "moon parent")
		_check(float(moon["radius_m"]) >= Bodies.MOON_RADIUS_MIN_M * (1.0 - 1.0e-12), "moon minimum radius")
		_check(float(moon["radius_m"]) <= Bodies.MOON_RADIUS_MAX_M * (1.0 + 1.0e-12), "moon maximum radius")
		_check(float(moon["radius_m"]) <= float(parent["radius_m"]) * 0.35 * (1.0 + 1.0e-12), "moon to parent radius")
		total += float(moon["mass_kg"])
	_check(total <= float(parent["mass_kg"]) * Bodies.MOON_TOTAL_MASS_FRACTION * (1.0 + 1.0e-12), "total moon mass budget")


func _initialize() -> void:
	var catalog = Catalog.new(Identity.universe_id("laniakeye-development-v1"), 1)
	for x: int in range(-2, 3):
		for y: int in range(-2, 3):
			for z: int in range(-2, 3):
				var sector: Dictionary = catalog.describe_sector(0, x, y, z)
				for source: Dictionary in sector["systems"]:
					var original: Dictionary = source.duplicate(true)
					var built: Dictionary = Bodies.build(source)
					_check(source == original, "source unchanged")
					_check(built == Bodies.build(source), "deterministic body descriptors")
					_check(built["orbit_layout_status"] == "not_built", "no premature orbit guarantee")
					_systems += 1
					for star: Dictionary in built["stars"]:
						_check_physical(star)
					for planet: Dictionary in built["planets"]:
						_check_physical(planet)
						_planets += 1
						var radius: float = planet["radius_m"]
						if planet["family"] == "gas_giant":
							_gas_giants += 1
							_check(radius > Bodies.SOLID_RADIUS_MAX_M and radius <= Bodies.GAS_RADIUS_MAX_M, "gas radius limits")
						else:
							_check(radius >= Bodies.SOLID_RADIUS_MIN_M and radius <= Bodies.SOLID_RADIUS_MAX_M, "solid radius limits")
							if radius < 1500000.0:
								_small_bodies += 1
						if _largest_parent.is_empty() or radius > float(_largest_parent["radius_m"]):
							_largest_parent = planet.duplicate(true)
						_check_moons(planet, planet["moons"])
						_moons += planet["moons"].size()

	_check(_gas_giants > 0 and _small_bodies > 0, "large and small sample coverage")
	if not _largest_parent.is_empty():
		var fixture: Dictionary = _largest_parent.duplicate(true)
		fixture["id"] = Identity.child_id(fixture["id"], "test_fixture", "115_moons")
		var moons: Array[Dictionary] = Bodies.make_moons(fixture, 115)
		_check(moons.size() == 115, "115-moon stress fixture")
		_check_moons(fixture, moons)
		_check(moons == Bodies.make_moons(fixture, 115), "stress fixture reproducibility")
	else:
		_check(false, "nonempty planet sample")
	print("BodyCatalog: systems=%d planets=%d natural_moons=%d gas_giants=%d small_solids=%d stress_moons=115" % [
		_systems, _planets, _moons, _gas_giants, _small_bodies,
	])
	if _failures == 0:
		print("BodyCatalog: PASS sizes, masses, hierarchy, determinism, 115-moon fixture")
	quit(0 if _failures == 0 else 1)
