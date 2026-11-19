class_name LkSystemPlacement
extends RefCounted

const Identity = preload("res://world/generation/lk_world_identity.gd")
const Samples = preload("res://world/generation/lk_world_samples.gd")
const Catalog = preload("res://world/generation/lk_world_catalog.gd")
const Bodies = preload("res://world/generation/lk_body_catalog.gd")
const Layout = preload("res://world/generation/lk_safe_orbit_layout.gd")
const OrbitValidator = preload("res://world/generation/lk_orbit_layout_validator.gd")

const VERSION: int = 1
const LIGHT_YEAR_M: float = 9460730472580800.0
const SECTOR_WIDTH_M: float = Catalog.SECTOR_WIDTH_LY * LIGHT_YEAR_M
const BOUNDARY_MARGIN_M: float = 149597870700.0


# Four nonoverlapping boxes partition a sector: 2 along X, 2 along Y, 1 along Z.
# A temporary spatial policy, not the final stellar density/morphology model.
static func _box(slot: int) -> Dictionary:
	if slot < 0 or slot >= 4:
		return {}
	var half: float = SECTOR_WIDTH_M * 0.5
	var x: float = float(slot & 1) * half
	var y: float = float((slot >> 1) & 1) * half
	return {"min": [x, y, 0.0], "max": [x + half, y + half, SECTOR_WIDTH_M]}


# Reconstruct the bound from orbit parameters and leaf body bounds.
# Call only after orbit layout validation succeeds.
static func system_bound_m(layout: Dictionary) -> float:
	var bound: float = layout["star"]["physical_bound_radius_m"]
	for planet: Dictionary in layout["planets"]:
		var local_bound: float = planet["body"]["physical_bound_radius_m"]
		for moon: Dictionary in planet["moons"]:
			var orbit: Dictionary = moon["orbit"]
			var edge: float = float(orbit["semi_major_axis_m"]) * (1.0 + float(orbit["eccentricity"]))
			edge += float(moon["body"]["physical_bound_radius_m"])
			local_bound = maxf(local_bound, edge)
		var orbit: Dictionary = planet["orbit"]
		var edge: float = float(orbit["semi_major_axis_m"]) * (1.0 + float(orbit["eccentricity"])) + local_bound
		bound = maxf(bound, edge)
	return bound


static func _consistent(
	source: Dictionary, layout: Dictionary, galaxy_id: String,
	x: int, y: int, z: int
) -> bool:
	if not Identity.is_valid_id(galaxy_id) or source.is_empty() or layout.is_empty():
		return false
	if int(source.get("catalog_version", -1)) != 1:
		return false
	var sector: String = Identity.child_id(galaxy_id, "sector", "%d/%d/%d" % [x, y, z])
	var slot: int = source.get("slot", -1)
	if slot < 0 or slot >= 4:
		return false
	if source.get("sector_id", "") != sector:
		return false
	if source.get("id", "") != Identity.child_id(sector, "system", str(slot)):
		return false
	return layout.get("system_id", "") == source["id"]


# Returns {} if layout is invalid or does not fit. Never shrinks a system.
static func place(
	source: Dictionary, layout: Dictionary, galaxy_id: String,
	x: int, y: int, z: int
) -> Dictionary:
	if not _consistent(source, layout, galaxy_id, x, y, z):
		return {}
	if not OrbitValidator.validate(layout).is_empty():
		return {}
	var bound: float = system_bound_m(layout)
	if not is_finite(bound) or bound <= 0.0:
		return {}
	var box: Dictionary = _box(source["slot"])
	var offset: Array[float] = []
	for axis: int in range(3):
		var first: float = float(box["min"][axis]) + bound + 2.0 * BOUNDARY_MARGIN_M
		var last: float = float(box["max"][axis]) - bound - 2.0 * BOUNDARY_MARGIN_M
		if first >= last:
			return {}
		var sample: float = Samples.unit(source["id"], "placement/axis_" + str(axis), VERSION)
		offset.append(first + (last - first) * sample)
	return {
		"placement_version": VERSION,
		"layout_version": layout["layout_version"],
		"system_id": source["id"], "galaxy_id": galaxy_id,
		"sector_id": source["sector_id"], "slot": source["slot"],
		"sector_address": {"x": str(x), "y": str(y), "z": str(z)},
		"offset_m": offset, "system_bound_m": bound,
	}


# Schema-structured data, not an arbitrary JSON parser.
static func validate(
	record: Dictionary, source: Dictionary, layout: Dictionary,
	galaxy_id: String, x: int, y: int, z: int
) -> Array[String]:
	var errors: Array[String] = []
	if not _consistent(source, layout, galaxy_id, x, y, z):
		errors.append("source/layout/address mismatch")
		return errors
	var orbit_errors: Array[String] = OrbitValidator.validate(layout)
	if not orbit_errors.is_empty():
		errors.append("invalid orbital layout: " + str(orbit_errors))
		return errors
	if int(record.get("placement_version", -1)) != VERSION:
		errors.append("unsupported or missing placement version")
		return errors
	if int(record.get("layout_version", -1)) != int(layout["layout_version"]):
		errors.append("layout version mismatch")
	if record.get("system_id", "") != source["id"] or record.get("galaxy_id", "") != galaxy_id or record.get("sector_id", "") != source["sector_id"]:
		errors.append("record identity mismatch")
	if int(record.get("slot", -1)) != int(source["slot"]):
		errors.append("slot mismatch")
	var expected: Dictionary = {"x": str(x), "y": str(y), "z": str(z)}
	if record.get("sector_address", {}) != expected:
		errors.append("sector address mismatch")
	var actual_bound: float = system_bound_m(layout)
	var stored_bound: float = record.get("system_bound_m", -1.0)
	if not is_finite(stored_bound) or absf(stored_bound - actual_bound) > maxf(0.001, actual_bound * 1.0e-12):
		errors.append("forged or invalid system bound")
	var offset: Array = record.get("offset_m", [])
	if offset.size() != 3:
		errors.append("invalid offset dimensions")
		return errors
	var box: Dictionary = _box(source["slot"])
	for axis: int in range(3):
		var coordinate: float = offset[axis]
		if not is_finite(coordinate):
			errors.append("nonfinite coordinate")
			continue
		if coordinate - actual_bound < float(box["min"][axis]) + BOUNDARY_MARGIN_M:
			errors.append("system crosses lower cell boundary")
		if coordinate + actual_bound > float(box["max"][axis]) - BOUNDARY_MARGIN_M:
			errors.append("system crosses upper cell boundary")
	return errors


static func describe_sector(catalog, galaxy_index: int, x: int, y: int, z: int) -> Dictionary:
	var sector: Dictionary = catalog.describe_sector(galaxy_index, x, y, z)
	var records: Array[Dictionary] = []
	var galaxy: String = catalog.galaxy_id(galaxy_index)
	for source: Dictionary in sector["systems"]:
		var physical: Dictionary = Bodies.build(source)
		var layout: Dictionary = Layout.build(physical)
		var record: Dictionary = place(source, layout, galaxy, x, y, z)
		if record.is_empty():
			push_error("SystemPlacement: system rejected; sector not published")
			return {}
		records.append(record)
	return {
		"sector_id": sector["id"], "galaxy_id": galaxy,
		"placement_version": VERSION, "systems": records,
	}
