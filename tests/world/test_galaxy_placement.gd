extends SceneTree

const Placement = preload("res://game/world/generation/lk_galaxy_placement.gd")
const Validator = preload("res://game/world/generation/lk_galaxy_placement_validator.gd")
const Catalog = preload("res://game/world/generation/lk_world_catalog.gd")
const Definition = preload("res://game/world/generation/lk_universe_definition.gd")
const Identity = preload("res://game/world/generation/lk_world_identity.gd")

var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("GalaxyPlacement: FAIL " + label)


func _initialize() -> void:
	var definition = Definition.new()
	var universe: String = definition.get_universe_id()
	var catalog = Catalog.new(universe, 1)
	var records: Array[Dictionary] = []
	for x: int in range(-2, 3):
		for y: int in range(-2, 3):
			for z: int in range(-2, 3):
				var index: int = Placement.index_from_cell(x, y, z)
				_check(Placement.cell_from_index(index) == [x, y, z], "cell/index round trip")
				var record: Dictionary = Placement.describe_galaxy(universe, index)
				_check(record["galaxy_id"] == catalog.galaxy_id(index), "existing catalog galaxy ID preserved")
				_check(Validator.validate(record, universe).is_empty(), "valid placement")
				_check(record == Placement.describe_cell(universe, x, y, z), "lookup by cell")
				records.append(record)
	var pairs: int = 0
	var minimum_clearance: float = INF
	for i: int in range(records.size()):
		for j: int in range(i + 1, records.size()):
			var clearance: float = Validator.pair_clearance_ly(records[i], records[j])
			minimum_clearance = minf(minimum_clearance, clearance)
			_check(clearance >= Placement.MIN_GAP_LY, "nonoverlapping envelopes with gap")
			var ab: Array[float] = Placement.relative_centres_ly(records[i], records[j])
			var ba: Array[float] = Placement.relative_centres_ly(records[j], records[i])
			var length_squared: float = 0.0
			for axis: int in range(3):
				_check(absf(ab[axis] + ba[axis]) < 1.0e-8, "relative vector antisymmetry")
				length_squared += ab[axis] * ab[axis]
			_check(absf(sqrt(length_squared) - float(records[i]["envelope_radius_ly"]) - float(records[j]["envelope_radius_ly"]) - clearance) < 1.0e-8, "relative vector/pair checker agree")
			pairs += 1
	for i: int in range(records.size() - 1, -1, -1):
		var index: int = String(records[i]["galaxy_index"]).to_int()
		_check(records[i] == Placement.describe_galaxy(universe, index), "reverse query order")
	for index: int in [0, 1, 2, 7, 8, 123456789, 9223372036854775807]:
		var cell: Array[int] = Placement.cell_from_index(index)
		_check(Placement.index_from_cell(cell[0], cell[1], cell[2]) == index, "int64 bijection")
		var record: Dictionary = Placement.describe_galaxy(universe, index)
		_check(Validator.validate(record, universe).is_empty(), "int64 galaxy placement")
		_check(record["galaxy_index"] == str(index), "exact index serialization")
	_check(Placement.index_from_cell(Placement.CELL_MAX + 1, 0, 0) == -1, "reject cell overflow")
	_check(Placement.describe_galaxy(universe, -1).is_empty(), "reject negative index")
	var home: Dictionary = Placement.describe_galaxy(universe, 0)
	var radius: float = home["envelope_radius_ly"]
	_check(Placement.contains_local_sphere(home, [0.0, 0.0, 0.0], radius), "full local envelope fits")
	_check(not Placement.contains_local_sphere(home, [radius, 0.0, 0.0], 1.0), "reject object beyond envelope")
	_check(not Placement.contains_local_sphere(home, [NAN, 0.0, 0.0], 1.0), "reject nonfinite local position")
	var rotated: Array[float] = Placement.rotate_local_ly(home, [3.0, 4.0, 0.0])
	_check(absf(sqrt(rotated[0] * rotated[0] + rotated[1] * rotated[1] + rotated[2] * rotated[2]) - 5.0) < 1.0e-12, "local rotation preserves lengths")
	var broken: Dictionary = home.duplicate(true)
	broken["center_offset_ly"][0] = Placement.CELL_WIDTH_LY
	_check(not Validator.validate(broken, universe).is_empty(), "reject boundary crossing")
	broken = home.duplicate(true)
	broken["galaxy_to_universe_axes"][0][0] += 0.1
	_check(not Validator.validate(broken, universe).is_empty(), "reject distorted orientation")
	broken = home.duplicate(true)
	for i: int in range(3):
		broken["galaxy_to_universe_axes"][0][i] *= -1.0
	_check(not Validator.validate(broken, universe).is_empty(), "reject reflected orientation")
	broken = home.duplicate(true)
	broken["cell_address"]["x"] = "1"
	_check(not Validator.validate(broken, universe).is_empty(), "reject forged address")
	broken = home.duplicate(true)
	broken["galaxy_index"] = "9223372036854775808"
	_check(not Validator.validate(broken, universe).is_empty(), "reject oversized index string")
	var other_universe: String = Identity.universe_id("galaxy-placement-test-other")
	_check(Placement.relative_centres_ly(home, Placement.describe_galaxy(other_universe, 0)).is_empty(), "separate universe namespaces")
	print("GalaxyPlacement: galaxies=%d pairs=%d min_clearance=%.3f ly home_radius=%.3f ly" % [records.size(), pairs, minimum_clearance, radius])
	if _failures == 0:
		print("GalaxyPlacement: PASS identity, cells, envelopes, orientation, int64, determinism, local bounds, negative fixtures")
	quit(0 if _failures == 0 else 1)
