class_name LkBodyContext
extends RefCounted

const Identity = preload("res://world/generation/lk_world_identity.gd")
const Catalog = preload("res://world/generation/lk_world_catalog.gd")
const Bodies = preload("res://world/generation/lk_body_catalog.gd")
const Layout = preload("res://world/generation/lk_safe_orbit_layout.gd")
const Validator = preload("res://world/generation/lk_orbit_layout_validator.gd")
const Placement = preload("res://world/generation/lk_system_placement.gd")


static func resolve(definition, galaxy_index: int, x: int, y: int, z: int, system_slot: int, planet_slot: int) -> Dictionary:
	if definition.terrain_version != 1:
		push_error("BodyContext: integration surface supports terrain version 1 only")
		return {}
	var universe: String = definition.get_universe_id()
	var catalog = Catalog.new(universe, definition.catalog_version)
	var source: Dictionary = catalog.describe_system(galaxy_index, x, y, z, system_slot)
	if source.is_empty():
		push_error("BodyContext: system does not exist")
		return {}
	var physical: Dictionary = Bodies.build(source)
	var layout: Dictionary = Layout.build(physical)
	if not Validator.validate(layout).is_empty():
		push_error("BodyContext: orbital layout rejected")
		return {}
	var placement: Dictionary = Placement.place(source, layout, catalog.galaxy_id(galaxy_index), x, y, z)
	if placement.is_empty():
		push_error("BodyContext: system placement rejected")
		return {}
	for entry: Dictionary in layout["planets"]:
		var body: Dictionary = entry["body"]
		if int(body["slot"]) != planet_slot:
			continue
		if body["family"] == "gas_giant":
			push_error("BodyContext: this surface scene cannot land on a gas giant")
			return {}
		var manifest: Dictionary = {
			"format": 1, "universe_id": universe, "body_id": body["id"],
			"catalog_version": definition.catalog_version,
			"body_schema_version": physical["body_schema_version"],
			"terrain_version": definition.terrain_version,
			"surface_recipe": "integration_sphere_v1",
			"radius_m": body["radius_m"],
		}
		return {
			"universe_id": universe, "body": body.duplicate(true),
			"orbit": entry["orbit"].duplicate(true), "spin": entry["spin"].duplicate(true),
			"placement": placement, "manifest": manifest,
			"address": {"galaxy": str(galaxy_index), "x": str(x), "y": str(y), "z": str(z),
				"system_slot": system_slot, "planet_slot": planet_slot},
		}
	push_error("BodyContext: planet does not exist")
	return {}
