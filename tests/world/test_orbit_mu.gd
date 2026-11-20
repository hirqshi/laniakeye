extends SceneTree

const Bodies = preload("res://world/generation/lk_body_catalog.gd")
const Layout = preload("res://world/generation/lk_safe_orbit_layout.gd")
const Validator = preload("res://world/generation/lk_orbit_layout_validator.gd")
const Catalog = preload("res://world/generation/lk_world_catalog.gd")
const Definition = preload("res://world/generation/lk_universe_definition.gd")
var _failures: int = 0
var _systems: int = 0
var _planets: int = 0
var _moons: int = 0
var _negative_checks: int = 0
var _minimum_star_mu: float = INF
var _maximum_star_mu: float = 0.0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		if _failures <= 16:
			push_error("OrbitMu: FAIL " + label)

func _body(body: Dictionary) -> void:
	var mass: float = body["mass_kg"]
	var mu: float = body["mu_m3_s2"]
	_check(is_finite(mass) and mass > 0.0 and is_finite(mu) and mu > 0.0, "positive finite mass and mu")
	_check(mu == Bodies.G_SI * mass, "catalog mu equals G times mass")

func _inspect(source: Dictionary) -> void:
	var physical: Dictionary = Bodies.build(source)
	var original: PackedByteArray = var_to_bytes(physical)
	var layout: Dictionary = Layout.build(physical)
	_check(var_to_bytes(physical) == original, "layout does not mutate physical catalog")
	_check(Validator.validate(layout).is_empty(), "baseline layout validates")
	var star: Dictionary = layout["star"]
	_body(star)
	_minimum_star_mu = minf(_minimum_star_mu, float(star["mu_m3_s2"]))
	_maximum_star_mu = maxf(_maximum_star_mu, float(star["mu_m3_s2"]))
	for i: int in range(layout["planets"].size()):
		var planet: Dictionary = layout["planets"][i]
		_body(planet["body"])
		_check(planet["orbit"]["primary_mu_m3_s2"] == star["mu_m3_s2"], "planet uses its star mu")
		_planets += 1
		for moon: Dictionary in planet["moons"]:
			_body(moon["body"])
			_check(moon["orbit"]["primary_mu_m3_s2"] == planet["body"]["mu_m3_s2"], "moon uses its planet mu")
			_moons += 1
		if i == 0:
			var broken: Dictionary = layout.duplicate(true)
			broken["planets"][i]["orbit"]["primary_mu_m3_s2"] = float(star["mu_m3_s2"]) * 1.01
			_check(Validator.validate(broken).has("orbit uses incorrect primary mu"), "validator rejects wrong stellar mu")
			_negative_checks += 1
			if not planet["moons"].is_empty():
				broken = layout.duplicate(true)
				broken["planets"][i]["moons"][0]["orbit"]["primary_mu_m3_s2"] = float(planet["body"]["mu_m3_s2"]) * 1.01
				_check(Validator.validate(broken).has("orbit uses incorrect primary mu"), "validator rejects wrong planetary mu")
				_negative_checks += 1
	_systems += 1

func _initialize() -> void:
	var definition = Definition.new()
	var catalog = Catalog.new(definition.get_universe_id(), 1)
	for x: int in range(-1, 2):
		for y: int in range(-1, 2):
			for z: int in range(-1, 2):
				var sector: Dictionary = catalog.describe_sector(0, x, y, z)
				for source: Dictionary in sector["systems"]:
					_inspect(source)
	_check(_systems > 1 and _planets > 0 and _moons > 0 and _negative_checks > 0, "nonempty coverage")
	_check(_maximum_star_mu > _minimum_star_mu, "stellar mu varies across generated masses")
	print("OrbitMu: systems=", _systems, " planets=", _planets, " moons=", _moons,
		" negative_checks=", _negative_checks, " star_mu_min=", _minimum_star_mu,
		" star_mu_max=", _maximum_star_mu)
	if _failures == 0:
		print("OrbitMu: PASS G*mass, stellar variation, planet/moon parents, validator rejection, input isolation")
	quit(0 if _failures == 0 else 1)
