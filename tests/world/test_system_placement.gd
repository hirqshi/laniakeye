extends SceneTree

const Identity = preload("res://world/generation/lk_world_identity.gd")
const Catalog = preload("res://world/generation/lk_world_catalog.gd")
const Bodies = preload("res://world/generation/lk_body_catalog.gd")
const Layout = preload("res://world/generation/lk_safe_orbit_layout.gd")
const Placement = preload("res://world/generation/lk_system_placement.gd")

var _failures: int = 0
var _records: Array[Dictionary] = []
var _sources: Array[Dictionary] = []
var _layouts: Array[Dictionary] = []
var _addresses: Array = []
var _minimum_separation_m: float = INF


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("SystemPlacement: FAIL " + label)


func _initialize() -> void:
	var catalog = Catalog.new(Identity.universe_id("laniakeye-development-v1"), 1)
	var galaxy: String = catalog.galaxy_id(0)
	for x: int in range(-2, 3):
		for y: int in range(-2, 3):
			for z: int in range(-2, 3):
				var sector: Dictionary = catalog.describe_sector(0, x, y, z)
				for source: Dictionary in sector["systems"]:
					var layout: Dictionary = Layout.build(Bodies.build(source))
					var record: Dictionary = Placement.place(source, layout, galaxy, x, y, z)
					_check(not record.is_empty(), "successful placement")
					if record.is_empty():
						continue
					var errors: Array[String] = Placement.validate(record, source, layout, galaxy, x, y, z)
					_check(errors.is_empty(), "cell containment: " + str(errors))
					_records.append(record)
					_sources.append(source)
					_layouts.append(layout)
					_addresses.append([x, y, z])

	# Direct Euclidean pair checks supplement the analytic cell proof.
	# Only small sector differences are converted to float, not huge global positions.
	var pair_count: int = 0
	var adjacent_pairs: int = 0
	for i: int in range(_records.size()):
		for j: int in range(i + 1, _records.size()):
			var first: Dictionary = _records[i]
			var second: Dictionary = _records[j]
			var distance_squared: float = 0.0
			var nearby: bool = true
			for axis: int in range(3):
				var delta_sector: int = int(_addresses[i][axis]) - int(_addresses[j][axis])
				if absi(delta_sector) > 1:
					nearby = false
				var delta: float = float(delta_sector) * Placement.SECTOR_WIDTH_M
				delta += float(first["offset_m"][axis]) - float(second["offset_m"][axis])
				distance_squared += delta * delta
			var clearance: float = sqrt(distance_squared) - float(first["system_bound_m"]) - float(second["system_bound_m"])
			_minimum_separation_m = minf(_minimum_separation_m, clearance)
			_check(clearance > 0.0, "system pair overlap")
			pair_count += 1
			if nearby and _addresses[i] != _addresses[j]:
				adjacent_pairs += 1

	for i: int in range(_records.size() - 1, -1, -1):
		var a: Array = _addresses[i]
		_check(_records[i] == Placement.place(_sources[i], _layouts[i], galaxy, a[0], a[1], a[2]),
			"reverse query order")
	_check(adjacent_pairs > 0, "cross-sector pair coverage")
	_check(not _records.is_empty(), "nonempty sample")
	if not _records.is_empty():
		var source: Dictionary = _sources[0]
		var layout: Dictionary = _layouts[0]
		var a: Array = _addresses[0]
		var forged: Dictionary = _records[0].duplicate(true)
		forged["system_bound_m"] = 1.0
		_check(not Placement.validate(forged, source, layout, galaxy, a[0], a[1], a[2]).is_empty(), "reject forged bound")
		forged = _records[0].duplicate(true)
		forged["offset_m"][0] = 0.0
		_check(not Placement.validate(forged, source, layout, galaxy, a[0], a[1], a[2]).is_empty(), "reject boundary crossing")
		forged = _records[0].duplicate(true)
		forged["slot"] = (int(source["slot"]) + 1) % 4
		_check(not Placement.validate(forged, source, layout, galaxy, a[0], a[1], a[2]).is_empty(), "reject altered slot")
		forged = _records[0].duplicate(true)
		forged["offset_m"][1] = NAN
		_check(not Placement.validate(forged, source, layout, galaxy, a[0], a[1], a[2]).is_empty(), "reject NaN offset")
		var oversized: Dictionary = layout.duplicate(true)
		oversized["planets"] = []
		oversized["star"]["radius_m"] = Placement.SECTOR_WIDTH_M
		oversized["star"]["physical_bound_radius_m"] = Placement.SECTOR_WIDTH_M
		_check(Placement.place(source, oversized, galaxy, a[0], a[1], a[2]).is_empty(), "reject oversized system without shrinking")

	# Address values near signed int64 limits must never be multiplied into global floats.
	var large_count: int = 0
	for x: int in [9223372036854775806, -9223372036854775807]:
		var sector: Dictionary = catalog.describe_sector(0, x, -1, 2)
		for source: Dictionary in sector["systems"]:
			var layout: Dictionary = Layout.build(Bodies.build(source))
			var record: Dictionary = Placement.place(source, layout, galaxy, x, -1, 2)
			_check(not record.is_empty(), "int64 sector placement")
			if not record.is_empty():
				_check(record["sector_address"]["x"] == str(x), "exact int64 address retention")
				_check(Placement.validate(record, source, layout, galaxy, x, -1, 2).is_empty(), "int64 cell containment")
				large_count += 1
	_check(large_count > 0, "int64 address sample coverage")
	var wrapped: Dictionary = Placement.describe_sector(catalog, 0, 0, 0, 0)
	_check(not wrapped.is_empty(), "sector wrapper")
	print("SystemPlacement: systems=%d pairs=%d cross_sector_pairs=%d int64_systems=%d min_clearance=%.6f ly" % [
		_records.size(), pair_count, adjacent_pairs, large_count,
		_minimum_separation_m / Placement.LIGHT_YEAR_M,
	])
	if _failures == 0:
		print("SystemPlacement: PASS envelopes, cells, neighboring sectors, order, int64, negative fixtures")
	quit(0 if _failures == 0 else 1)
