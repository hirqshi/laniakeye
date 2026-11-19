class_name LkPopulationAudit
extends RefCounted

const Identity = preload("res://world/generation/lk_world_identity.gd")
const Samples = preload("res://world/generation/lk_world_samples.gd")
const Catalog = preload("res://world/generation/lk_world_catalog.gd")
const Galaxies = preload("res://world/generation/lk_galaxy_placement.gd")
const Spatial = preload("res://world/runtime/lk_universe_spatial.gd")
const Photo = preload("res://world/generation/lk_stellar_photometry.gd")

# Exact LIGHTWEIGHT read model of catalog v1, covered by comparison tests.
# Does NOT create physical planets, moons, orbital layouts or star positions.
static func sector_header(universe_id: String, galaxy_index: int, x: int, y: int, z: int) -> Dictionary:
	if not Identity.is_valid_id(universe_id) or galaxy_index < 0:
		return {}
	var galaxy_id: String = Identity.child_id(universe_id, "galaxy", str(galaxy_index))
	var sector_id: String = Identity.child_id(galaxy_id, "sector", "%d/%d/%d" % [x, y, z])
	var count: int = Samples.range_int(sector_id, "catalog/system_count", 1, 0, Catalog.MAX_SYSTEMS_PER_SECTOR)
	var systems: Array[Dictionary] = []
	var planets: int = 0
	for slot: int in range(count):
		var id: String = Identity.child_id(sector_id, "system", str(slot))
		var planet_count: int = 0
		if Samples.unit(id, "catalog/has_planets", 1) < 0.8:
			planet_count = Samples.range_int(id, "catalog/planet_count", 1, 1, 10)
		planets += planet_count
		systems.append({"system_id": id, "star_id": Identity.child_id(id, "star", "0"), "slot": slot, "planet_count": planet_count})
	return {"sector_id": sector_id, "systems": systems, "planet_count": planets}


static func expected_population(radius_ly: float) -> Dictionary:
	if not is_finite(radius_ly) or radius_ly <= 0.0:
		return {"ok": false}
	var mean_systems_sector: float = float(Catalog.MAX_SYSTEMS_PER_SECTOR) * 0.5
	var density: float = mean_systems_sector / pow(Catalog.SECTOR_WIDTH_LY, 3.0)
	var systems: float = (4.0 / 3.0) * PI * pow(radius_ly, 3.0) * density
	return {"ok": true, "expected_systems": systems,
		"expected_planets": systems * 0.8 * 5.5,
		"expected_solid_planets": systems * 0.8 * 5.5 * (2.0 / 3.0),
		"expected_gas_giants": systems * 0.8 * 5.5 / 3.0}


static func universe_expectation() -> Dictionary:
	# Log-uniform galaxy radius -> E[R^3], NOT (E[R])^3.
	var mean_cube: float = (pow(Galaxies.MAX_RADIUS_LY, 3.0) - pow(Galaxies.MIN_RADIUS_LY, 3.0)) / (3.0 * log(Galaxies.MAX_RADIUS_LY / Galaxies.MIN_RADIUS_LY))
	var mean_systems: float = (4.0 / 3.0) * PI * mean_cube * (float(Catalog.MAX_SYSTEMS_PER_SECTOR) * 0.5) / pow(Catalog.SECTOR_WIDTH_LY, 3.0)
	return {"galaxy_capacity_exact": "9223372036854775808",
		"expected_planets_per_galaxy": mean_systems * 4.4,
		"expected_planets_addressable_universe": mean_systems * 4.4 * pow(2.0, 63.0)}


# Conservative BOUNDS, not exact star locations. SystemPlacement v1 confines
# slot to X/Y half-sector boxes, full-sector Z. Point is star-relative metres.
static func coverage(observer: Dictionary, radius_ly: float, limit_proxy: float = 6.0,
	observer_point_m: Array = [0.0, 0.0, 0.0]) -> Dictionary:
	if not is_finite(radius_ly) or radius_ly < 0.0 or radius_ly > 128.0 or not is_finite(limit_proxy):
		return {"ok": false, "code": "invalid_parameters"}
	var valid: Dictionary = Spatial.relative(observer, observer, observer_point_m, observer_point_m)
	if not valid["ok"]:
		return valid
	var s: Dictionary = observer["system"]
	if s["placement_version"] != 1:
		return {"ok": false, "code": "unsupported_placement_recipe"}
	var galaxy: Dictionary = observer["galaxy"]
	var base: Array[int] = []
	var point: Array[float] = []
	var lower: Array[int] = []
	var upper: Array[int] = []
	var width: float = Catalog.SECTOR_WIDTH_LY
	for i: int in range(3):
		var key: String = ["x", "y", "z"][i]
		base.append(String(s["sector_address"][key]).to_int())
		point.append(float(s["offset_m"][i]) / Spatial.LY_M + float(observer_point_m[i]) / Spatial.LY_M)
		lower.append(int(floor((point[i] - radius_ly) / width)))
		upper.append(int(floor((point[i] + radius_ly) / width)))
	var spatial_lo: int = 0
	var spatial_hi: int = 0
	var visible_lo: int = 0
	var visible_hi: int = 0
	var sectors: int = 0
	var raw_systems: int = 0
	for dx: int in range(lower[0], upper[0] + 1):
		for dy: int in range(lower[1], upper[1] + 1):
			for dz: int in range(lower[2], upper[2] + 1):
				var delta: Array[int] = [dx, dy, dz]
				var address: Array[int] = [base[0] + dx, base[1] + dy, base[2] + dz]
				if not Spatial.sector_may_intersect(galaxy, address[0], address[1], address[2]):
					continue
				var sector_far_squared: float = 0.0
				for i: int in range(3):
					var lo: float = float(address[i]) * width
					var hi: float = lo + width
					sector_far_squared += maxf(absf(lo), absf(hi)) * maxf(absf(lo), absf(hi))
				var whole_sector_admitted: bool = sqrt(sector_far_squared) + Spatial.BOUNDARY_PAD_LY <= float(galaxy["envelope_radius_ly"])
				var header: Dictionary = sector_header(observer["universe_id"], String(galaxy["galaxy_index"]).to_int(), address[0], address[1], address[2])
				sectors += 1
				raw_systems += header["systems"].size()
				for system: Dictionary in header["systems"]:
					if system["system_id"] == s["system_id"]:
						continue
					var slot: int = system["slot"]
					var nearest_squared: float = 0.0
					var farthest_squared: float = 0.0
					for i: int in range(3):
						var cell_lo: float = 0.0
						var cell_width: float = width
						if i < 2:
							cell_width = width * 0.5
							cell_lo = float((slot >> i) & 1) * cell_width
						var lo: float = float(delta[i]) * width + cell_lo - point[i]
						var hi: float = lo + cell_width
						var nearest: float = lo if lo > 0.0 else (hi if hi < 0.0 else 0.0)
						var farthest: float = maxf(absf(lo), absf(hi))
						nearest_squared += nearest * nearest
						farthest_squared += farthest * farthest
					if nearest_squared > radius_ly * radius_ly:
						continue
					spatial_hi += 1
					var guaranteed: bool = whole_sector_admitted and farthest_squared <= radius_ly * radius_ly
					if guaranteed:
						spatial_lo += 1
					var photo: Dictionary = Photo.describe_star(system["star_id"])
					var brightest: float = -INF if nearest_squared == 0.0 else Photo.apparent_magnitude(photo["absolute_magnitude_proxy"], sqrt(nearest_squared))
					var faintest: float = Photo.apparent_magnitude(photo["absolute_magnitude_proxy"], sqrt(farthest_squared))
					if brightest <= limit_proxy:
						visible_hi += 1
					if guaranteed and faintest <= limit_proxy:
						visible_lo += 1
	return {"ok": true, "radius_ly": radius_ly, "limit_magnitude_proxy": limit_proxy,
		"spatial_lower": spatial_lo, "spatial_upper": spatial_hi,
		"photometric_lower": visible_lo, "photometric_upper": visible_hi,
		"queried_sectors": sectors, "raw_systems_in_boxes": raw_systems,
		"uses_exact_centres": false, "planet_moon_builds_in_audit": 0}
