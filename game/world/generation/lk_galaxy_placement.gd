class_name LkGalaxyPlacement
extends RefCounted

const Identity = preload("res://game/world/generation/lk_world_identity.gd")
const Samples = preload("res://game/world/generation/lk_world_samples.gd")
const VERSION: int = 1
# Explicit prototype DESIGN settings, not measured astronomical distributions.
const CELL_WIDTH_LY: float = 4000000.0
const MIN_RADIUS_LY: float = 20000.0
const MAX_RADIUS_LY: float = 200000.0
const MIN_GAP_LY: float = 500000.0
const NUMERIC_PAD_LY: float = 1.0
const CELL_MIN: int = -1048576
const CELL_MAX: int = 1048575


static func _u(id: String, key: String) -> float:
	return Samples.unit(id, "galaxy_placement/" + key, VERSION)


# Nonnegative signed int64 index <-> three signed 21-bit cell coordinates.
# The mapping is bijective, not a hash, so no two galaxy indices share a cell.
static func cell_from_index(index: int) -> Array[int]:
	var result: Array[int] = []
	if index < 0:
		return result
	for axis: int in range(3):
		var bits: int = 0
		for bit: int in range(21):
			bits |= ((index >> (3 * bit + axis)) & 1) << bit
		var signed_value: int = bits >> 1
		if (bits & 1) != 0:
			signed_value = -signed_value - 1
		result.append(signed_value)
	return result


static func index_from_cell(x: int, y: int, z: int) -> int:
	var values: Array[int] = [x, y, z]
	var index: int = 0
	for axis: int in range(3):
		var value: int = values[axis]
		if value < CELL_MIN or value > CELL_MAX:
			return -1
		var bits: int = value * 2 if value >= 0 else -value * 2 - 1
		for bit: int in range(21):
			index |= ((bits >> bit) & 1) << (3 * bit + axis)
	return index


# Uniform random orientation via a unit quaternion, computed in double scalars.
# Columns map GALAXY-local axes into UNIVERSE axes; not Euler angles.
static func _axes(id: String) -> Array:
	var u: float = _u(id, "orientation/u")
	var a: float = TAU * _u(id, "orientation/a")
	var b: float = TAU * _u(id, "orientation/b")
	var x: float = sqrt(1.0 - u) * sin(a)
	var y: float = sqrt(1.0 - u) * cos(a)
	var z: float = sqrt(u) * sin(b)
	var w: float = sqrt(u) * cos(b)
	return [
		[1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y + z * w), 2.0 * (x * z - y * w)],
		[2.0 * (x * y - z * w), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z + x * w)],
		[2.0 * (x * z + y * w), 2.0 * (y * z - x * w), 1.0 - 2.0 * (x * x + y * y)],
	]


static func describe_galaxy(universe_id: String, index: int) -> Dictionary:
	if not Identity.is_valid_id(universe_id) or index < 0:
		return {}
	var id: String = Identity.child_id(universe_id, "galaxy", str(index))
	var cell: Array[int] = cell_from_index(index)
	var radius: float = clampf(exp(log(MIN_RADIUS_LY) + _u(id, "radius") * log(MAX_RADIUS_LY / MIN_RADIUS_LY)), MIN_RADIUS_LY, MAX_RADIUS_LY)
	var available: float = CELL_WIDTH_LY * 0.5 - radius - MIN_GAP_LY * 0.5 - NUMERIC_PAD_LY
	var offset: Array[float] = []
	for axis: int in range(3):
		offset.append((2.0 * _u(id, "offset/" + str(axis)) - 1.0) * available)
	return {
		"placement_version": VERSION, "universe_id": universe_id,
		"galaxy_id": id, "galaxy_index": str(index),
		"cell_address": {"x": str(cell[0]), "y": str(cell[1]), "z": str(cell[2])},
		"center_offset_ly": offset, "envelope_radius_ly": radius,
		"galaxy_to_universe_axes": _axes(id),
	}


static func describe_cell(universe_id: String, x: int, y: int, z: int) -> Dictionary:
	var index: int = index_from_cell(x, y, z)
	return {} if index < 0 else describe_galaxy(universe_id, index)


# Input records must first pass independent LkGalaxyPlacementValidator.validate.
# Small integer cell differences are computed BEFORE conversion to float.
# Result is a far-rendering distance, NEVER a planet-surface physics position.
static func relative_centres_ly(target: Dictionary, observer: Dictionary) -> Array[float]:
	var result: Array[float] = []
	if target["universe_id"] != observer["universe_id"]:
		return result
	for axis: int in range(3):
		var key: String = ["x", "y", "z"][axis]
		var delta: int = String(target["cell_address"][key]).to_int() - String(observer["cell_address"][key]).to_int()
		result.append(float(delta) * CELL_WIDTH_LY + float(target["center_offset_ly"][axis]) - float(observer["center_offset_ly"][axis]))
	return result


static func rotate_local_ly(record: Dictionary, point: Array) -> Array[float]:
	var axes: Array = record["galaxy_to_universe_axes"]
	var result: Array[float] = []
	for axis: int in range(3):
		result.append(float(axes[0][axis]) * float(point[0]) + float(axes[1][axis]) * float(point[1]) + float(axes[2][axis]) * float(point[2]))
	return result


# Admissible galaxy volume. Existing catalog can still describe sectors outside
# this envelope; callers COMPOSING a universe must explicitly enforce this gate.
static func contains_local_sphere(record: Dictionary, center_ly: Array, radius_ly: float) -> bool:
	if center_ly.size() != 3 or not is_finite(radius_ly) or radius_ly < 0.0:
		return false
	var squared: float = 0.0
	for value in center_ly:
		if not is_finite(float(value)):
			return false
		squared += float(value) * float(value)
	return sqrt(squared) + radius_ly <= float(record["envelope_radius_ly"])
