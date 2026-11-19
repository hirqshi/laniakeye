class_name LkBodyCatalog
extends RefCounted

const Identity = preload("res://world/generation/lk_world_identity.gd")
const Samples = preload("res://world/generation/lk_world_samples.gd")

const BODY_SCHEMA_VERSION: int = 1
const G_SI: float = 6.67430e-11
const SOLAR_MASS_KG: float = 1.98847e30
const SOLAR_RADIUS_M: float = 695700000.0
const SOLID_RADIUS_MAX_M: float = 13000000.0
const JUPITER_REFERENCE_RADIUS_M: float = 71492000.0
const GAS_RADIUS_MAX_M: float = 2.0 * JUPITER_REFERENCE_RADIUS_M
const SOLID_RADIUS_MIN_M: float = 200000.0
const MOON_RADIUS_MIN_M: float = 100.0
const MOON_RADIUS_MAX_M: float = 2700000.0
const MOON_TOTAL_MASS_FRACTION: float = 0.03
# Defensive request limit for this prototype, not a claim about nature.
const MAX_REQUESTED_MOONS: int = 512


static func _u(id: String, property: String) -> float:
	return Samples.unit(id, "bodies/" + property, BODY_SCHEMA_VERSION)


static func sphere_mass(radius_m: float, density_kg_m3: float) -> float:
	return (4.0 / 3.0) * PI * radius_m * radius_m * radius_m * density_kg_m3


static func _physical(
	id: String, parent_id: String, kind: String, family: String,
	slot: int, radius: float, density: float
) -> Dictionary:
	var mass: float = sphere_mass(radius, density)
	var relief: float = 0.0
	if family != "gas_giant":
		relief = minf(200000.0, radius * 0.05)
	return {
		"id": id,
		"parent_id": parent_id,
		"kind": kind,
		"family": family,
		"slot": slot,
		"body_schema_version": BODY_SCHEMA_VERSION,
		"radius_m": radius,
		"density_kg_m3": density,
		"mass_kg": mass,
		"mu_m3_s2": G_SI * mass,
		"surface_gravity_m_s2": G_SI * mass / (radius * radius),
		"max_relief_m": relief,
		"physical_bound_radius_m": radius + relief,
	}


# Creates a NEW descriptor; does not modify catalogue v1 inputs.
static func build(system: Dictionary) -> Dictionary:
	if system.is_empty() or int(system.get("catalog_version", -1)) != 1:
		push_error("LkBodyCatalog: expected catalog v1 system")
		return {}
	var source_stars: Array = system["stars"]
	if source_stars.size() != 1:
		push_error("LkBodyCatalog: only single-star source systems supported")
		return {}
	var source_star: Dictionary = source_stars[0]
	var star_id: String = source_star["id"]
	var star_mass: float = SOLAR_MASS_KG * (0.5 + _u(star_id, "star_mass"))
	var star_radius: float = SOLAR_RADIUS_M * pow(star_mass / SOLAR_MASS_KG, 0.8)
	var star: Dictionary = {
		"id": star_id, "parent_id": system["id"], "kind": "star", "slot": 0,
		"body_schema_version": BODY_SCHEMA_VERSION,
		"mass_kg": star_mass, "mu_m3_s2": G_SI * star_mass,
		"radius_m": star_radius, "physical_bound_radius_m": star_radius,
	}
	var planets: Array[Dictionary] = []
	for source: Dictionary in system["planets"]:
		var planet: Dictionary = describe_planet(source)
		if planet.is_empty():
			return {}
		var count: int = natural_moon_count(planet)
		planet["moons"] = make_moons(planet, count)
		planets.append(planet)
	return {
		"system_id": system["id"],
		"catalog_version": 1,
		"body_schema_version": BODY_SCHEMA_VERSION,
		"orbit_layout_status": "not_built",
		"stars": [star],
		"planets": planets,
	}


static func describe_planet(source: Dictionary) -> Dictionary:
	var id: String = source.get("id", "")
	if not Identity.is_valid_id(id):
		push_error("LkBodyCatalog: invalid planet ID")
		return {}
	var family: String = source.get("family_hint", "")
	if family not in ["rocky", "icy", "gas_giant"]:
		push_error("LkBodyCatalog: unsupported family")
		return {}
	var radius: float
	var density: float
	if family == "gas_giant":
		radius = SOLID_RADIUS_MAX_M + 1.0 + (
			GAS_RADIUS_MAX_M - SOLID_RADIUS_MAX_M - 1.0
		) * _u(id, "radius")
		density = 300.0 + 1700.0 * _u(id, "density")
	else:
		var r0: float = 1500000.0
		var r1: float = SOLID_RADIUS_MAX_M
		if _u(id, "small_body") < 0.25:
			r0 = SOLID_RADIUS_MIN_M
			r1 = 1500000.0
		radius = r0 + (r1 - r0) * _u(id, "radius")
		if family == "icy":
			density = 1000.0 + 2500.0 * _u(id, "density")
		else:
			density = 2500.0 + 4500.0 * _u(id, "density")
	return _physical(
		id, source["primary_id"], "planet", family,
		int(source["slot"]), radius, density
	)


static func natural_moon_count(planet: Dictionary) -> int:
	var sample: float = _u(planet["id"], "moon_count")
	if planet["family"] == "gas_giant":
		return int(floor(sample * sample * sample * 181.0))
	return int(floor(sample * sample * sample * 9.0))


# Explicit count permits stress fixtures without changing production generation.
# Equal upper mass budgets are conservative, not a physical formation model.
static func make_moons(parent: Dictionary, count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if count < 0 or count > MAX_REQUESTED_MOONS:
		push_error("LkBodyCatalog: invalid requested moon count")
		return result
	if count == 0:
		return result
	var parent_id: String = parent["id"]
	var budget: float = float(parent["mass_kg"]) * MOON_TOTAL_MASS_FRACTION / float(count)
	for slot: int in range(count):
		var id: String = Identity.child_id(parent_id, "moon", str(slot))
		var density: float = 1000.0 + 3000.0 * _u(id, "density")
		var mass_radius: float = pow(budget / ((4.0 / 3.0) * PI * density), 1.0 / 3.0)
		var upper: float = minf(
			MOON_RADIUS_MAX_M,
			minf(float(parent["radius_m"]) * 0.35, mass_radius)
		)
		if upper < MOON_RADIUS_MIN_M:
			push_error("LkBodyCatalog: moon mass budget cannot support minimum radius")
			result.clear()
			return result
		var sample: float = _u(id, "radius")
		var radius: float = exp(
			log(MOON_RADIUS_MIN_M)
			+ sample * sample * (log(upper) - log(MOON_RADIUS_MIN_M))
		)
		var moon: Dictionary = _physical(
			id, parent_id, "moon", "solid_moon", slot, radius, density
		)
		result.append(moon)
	return result
