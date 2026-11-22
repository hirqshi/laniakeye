class_name LkWorldCatalog
extends RefCounted

const Identity = preload("res://game/world/generation/lk_world_identity.gd")
const Samples = preload("res://game/world/generation/lk_world_samples.gd")

# Technical distributions only, not the final galaxy model.
const SECTOR_WIDTH_LY: float = 16.0
const MAX_SYSTEMS_PER_SECTOR: int = 4
const EARTH_RADIUS_M: float = 6371000.0

var _root: String
var _version: int


func _init(universe_id: String, catalog_version: int = 1) -> void:
	_root = universe_id
	_version = catalog_version


func _valid() -> bool:
	if not Identity.is_valid_id(_root) or _version != 1:
		push_error("LkWorldCatalog: invalid root or unsupported catalog version")
		return false
	return true


func galaxy_id(galaxy_index: int) -> String:
	if not _valid() or galaxy_index < 0:
		return ""
	return Identity.child_id(_root, "galaxy", str(galaxy_index))


func sector_id(galaxy_index: int, x: int, y: int, z: int) -> String:
	var galaxy: String = galaxy_id(galaxy_index)
	if galaxy.is_empty():
		return ""
	return Identity.child_id(galaxy, "sector", "%d/%d/%d" % [x, y, z])


func _system_count(sector: String) -> int:
	return Samples.range_int(
		sector, "catalog/system_count", _version, 0, MAX_SYSTEMS_PER_SECTOR
	)


func describe_sector(galaxy_index: int, x: int, y: int, z: int) -> Dictionary:
	var sector: String = sector_id(galaxy_index, x, y, z)
	if sector.is_empty():
		return {}
	var systems: Array[Dictionary] = []
	for slot: int in range(_system_count(sector)):
		systems.append(describe_system(galaxy_index, x, y, z, slot))
	return {
		"id": sector,
		"galaxy_id": galaxy_id(galaxy_index),
		"catalog_version": _version,
		"address": {
			"galaxy": str(galaxy_index),
			"x": str(x), "y": str(y), "z": str(z),
		},
		"width_ly": SECTOR_WIDTH_LY,
		"systems": systems,
	}


func describe_system(
	galaxy_index: int, x: int, y: int, z: int, slot: int
) -> Dictionary:
	var sector: String = sector_id(galaxy_index, x, y, z)
	if sector.is_empty():
		return {}
	if slot < 0 or slot >= _system_count(sector):
		return {}
	var system: String = Identity.child_id(sector, "system", str(slot))
	var star: String = Identity.child_id(system, "star", "0")
	var planets: Array[Dictionary] = []
	var planet_count: int = 0
	if Samples.unit(system, "catalog/has_planets", _version) < 0.8:
		planet_count = Samples.range_int(
			system, "catalog/planet_count", _version, 1, 10
		)
	for planet_slot: int in range(planet_count):
		planets.append(_describe_planet(system, star, planet_slot))
	return {
		"id": system,
		"sector_id": sector,
		"catalog_version": _version,
		"slot": slot,
		"offset_ly": [
			Samples.unit(system, "catalog/offset_x", _version) * SECTOR_WIDTH_LY,
			Samples.unit(system, "catalog/offset_y", _version) * SECTOR_WIDTH_LY,
			Samples.unit(system, "catalog/offset_z", _version) * SECTOR_WIDTH_LY,
		],
		"stars": [{"id": star, "kind": "star", "slot": 0}],
		"planets": planets,
	}


func _describe_planet(system: String, star: String, slot: int) -> Dictionary:
	var planet: String = Identity.child_id(system, "planet", str(slot))
	var families: PackedStringArray = PackedStringArray([
		"rocky", "icy", "gas_giant",
	])
	var family_index: int = Samples.range_int(
		planet, "catalog/family", _version, 0, families.size() - 1
	)
	var family: String = families[family_index]
	var radius_sample: float = Samples.unit(planet, "catalog/radius", _version)
	var radius_m: float = EARTH_RADIUS_M * (0.33 + 1.67 * radius_sample)
	if family == "gas_giant":
		radius_m = EARTH_RADIUS_M * (3.0 + 8.0 * radius_sample)
	return {
		"id": planet,
		"system_id": system,
		"primary_id": star,
		"kind": "planet",
		"slot": slot,
		"family_hint": family,
		"radius_m": radius_m,
	}
