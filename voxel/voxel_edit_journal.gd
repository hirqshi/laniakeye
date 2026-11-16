class_name LkVoxelEditJournal
extends RefCounted

# Five scalar values per operation:
# center_x, center_y, center_z, radius_m, build_flag.
const RECORD_SIZE: int = 5

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
	if center == null:
		push_error("VoxelEditJournal: null center")
		return false

	if (
		not is_finite(center.x)
		or not is_finite(center.y)
		or not is_finite(center.z)
		or not is_finite(radius_m)
		or radius_m <= 0.0
	):
		push_error("VoxelEditJournal: invalid sphere")
		return false

	_records.append(center.x)
	_records.append(center.y)
	_records.append(center.z)
	_records.append(radius_m)
	_records.append(1.0 if build else 0.0)

	_revision += 1
	return true


# Return a detached copy. Do not give generators the live journal.
func copy_records() -> PackedFloat64Array:
	return _records.duplicate()
