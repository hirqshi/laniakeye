extends SceneTree

const Identity = preload("res://game/world/generation/lk_world_identity.gd")
const Samples = preload("res://game/world/generation/lk_world_samples.gd")
const Definition = preload("res://game/world/generation/lk_universe_definition.gd")
const Catalog = preload("res://game/world/generation/lk_world_catalog.gd")

var _failures: int = 0
var _seen: Dictionary = {}


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error("WorldCatalog: FAIL " + label)


func _remember(id: String) -> void:
	_check(Identity.is_valid_id(id), "canonical ID")
	_check(not _seen.has(id), "duplicate ID in sample")
	_seen[id] = true


func _initialize() -> void:
	var definition = Definition.new()
	var catalog = Catalog.new(definition.get_universe_id(), definition.catalog_version)
	var baseline: Dictionary = catalog.describe_sector(0, 0, 0, 0)
	_check(catalog.galaxy_id(0) == "fc24fa78437707bf767d97c1553939fe", "galaxy reference")
	_check(baseline.get("id", "") == "96f5f0e3d8164f751b4cd7683c629459", "sector reference")
	_check(baseline["systems"].size() == 1, "count reference")
	_check(catalog.sector_id(0, -1, 2, 3) != catalog.sector_id(0, 1, 2, 3),
		"signed coordinate sample")
	_check(catalog.sector_id(0, 2147483648, 0, 0) !=
		catalog.sector_id(0, -2147483648, 0, 0), "64-bit coordinate sample")
	var reference_system: String = Identity.child_id(baseline["id"], "system", "0")
	_check(reference_system == "5820d532ed6d16e5ecafa04938ae7b85", "system reference")
	var reference_seed: int = Identity.seed63(
		reference_system,
		"catalog/offset_x",
		1
	)
	var reference_bits: int = reference_seed >> 10

	var actual_sample: float = Samples.unit(
		reference_system,
		"catalog/offset_x",
		1
	)
	var expected_sample: float = (
		float(380114247880983) / float(9007199254740992)
	)

	_check(
		reference_seed == 389236989830127204,
		"sampler seed reference"
	)
	_check(
		reference_bits == 380114247880983,
		"sampler 53-bit integer reference"
	)
	_check(
		actual_sample == expected_sample,
		"sampler conversion reference"
	)

	print(
		"WorldSamples: seed=%d bits=%d actual=%.17f expected=%.17f"
		% [
			reference_seed,
			reference_bits,
			actual_sample,
			expected_sample,
		]
	)

	var system_count: int = 0
	var planet_count: int = 0
	for x: int in range(-2, 3):
		for y: int in range(-2, 3):
			for z: int in range(-2, 3):
				var sector: Dictionary = catalog.describe_sector(0, x, y, z)
				_remember(sector["id"])
				for system: Dictionary in sector["systems"]:
					_remember(system["id"])
					system_count += 1
					_check(system == catalog.describe_system(0, x, y, z, system["slot"]),
						"direct query equals sector query")
					for coordinate: float in system["offset_ly"]:
						_check(coordinate >= 0.0 and coordinate < Catalog.SECTOR_WIDTH_LY,
							"local position bounds")
					for star: Dictionary in system["stars"]:
						_remember(star["id"])
					for planet: Dictionary in system["planets"]:
						_remember(planet["id"])
						planet_count += 1
						_check(planet["system_id"] == system["id"], "planet parent")
						_check(planet["radius_m"] > 0.0, "positive radius")

	_check(baseline == catalog.describe_sector(0, 0, 0, 0), "query order independence")
	var changed: Dictionary = catalog.describe_sector(0, 0, 0, 0)
	changed["systems"].append({"id": "mutated"})
	_check(baseline == catalog.describe_sector(0, 0, 0, 0), "returned data isolation")
	var other = Catalog.new(Identity.universe_id("another-development-universe"), 1)
	_check(other.sector_id(0, 0, 0, 0) != baseline["id"], "universe separation")
	print("WorldCatalog: sectors=125 systems=%d planets=%d unique_ids=%d" % [
		system_count, planet_count, _seen.size(),
	])
	if _failures == 0:
		print("WorldCatalog: PASS references, addressing, bounds, order, isolation")
	quit(0 if _failures == 0 else 1)
