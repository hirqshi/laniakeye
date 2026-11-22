class_name LkVoxelEditJournal
extends RefCounted

# Legacy record:
# center_x, center_y, center_z, radius_m, build_flag.
#
# Version 2 record:
# center_x, center_y, center_z, radius_m, build_flag, mode, amount_m.
#
# MODE_FULL applies the complete spherical SDF operation, preserving the
# behaviour of journals created before partial editing existed.
# MODE_PARTIAL moves the current SDF toward that target by at most amount_m.
const RECORD_SIZE: int = 7
const MODE_FULL: int = 0
const MODE_PARTIAL: int = 1

var _records: PackedFloat64Array = []
var _revision: int = 0


func get_revision() -> int:
	return _revision


func get_count() -> int:
	return _records.size() / RECORD_SIZE


func append_sphere(
	center: LkPosition64,
	radius_m: float,
	build: bool
) -> bool:
	return _append(
		center,
		radius_m,
		build,
		MODE_FULL,
		0.0
	)


func append_partial_sdf(
	center: LkPosition64,
	radius_m: float,
	build: bool,
	amount_m: float
) -> bool:
	return _append(
		center,
		radius_m,
		build,
		MODE_PARTIAL,
		amount_m
	)


func _append(
	center: LkPosition64,
	radius_m: float,
	build: bool,
	mode: int,
	amount_m: float
) -> bool:
	if center == null:
		push_error("VoxelEditJournal: null center")
		return false

	if (
		not is_finite(center.x)
		or not is_finite(center.y)
		or not is_finite(center.z)
		or not is_finite(radius_m)
		or radius_m <= 0.0
		or mode not in [MODE_FULL, MODE_PARTIAL]
		or not is_finite(amount_m)
		or (mode == MODE_PARTIAL and amount_m <= 0.0)
	):
		push_error("VoxelEditJournal: invalid operation")
		return false

	_records.append(center.x)
	_records.append(center.y)
	_records.append(center.z)
	_records.append(radius_m)
	_records.append(1.0 if build else 0.0)
	_records.append(float(mode))
	_records.append(amount_m)

	_revision += 1
	return true


func get_mode(index: int) -> int:
	var offset: int = index * RECORD_SIZE

	if offset + 5 >= _records.size():
		return MODE_FULL

	return int(_records[offset + 5])


func get_amount(index: int) -> float:
	var offset: int = index * RECORD_SIZE

	if offset + 6 >= _records.size():
		return 0.0

	return _records[offset + 6]


func remove_last() -> bool:
	if _records.size() < RECORD_SIZE:
		return false

	_records.resize(_records.size() - RECORD_SIZE)
	_revision -= 1
	return true


# Return a detached copy. Do not give generators the live journal.
func copy_records() -> PackedFloat64Array:
	return _records.duplicate()
