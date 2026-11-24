class_name LkCoordinateFrame
extends RefCounted

signal shifted(local_delta: Vector3)

var threshold_m: float = 512.0
var _origin: LkPosition64 = LkPosition64.new()
var _roots: Array[Node3D] = []

func get_origin() -> LkPosition64:
	return _origin.copy()

func initialize_origin(value: LkPosition64) -> bool:
	if not _roots.is_empty():
		push_error("CoordinateFrame: initialize origin before registering roots")
		return false
	_origin = value.copy()
	return true

func to_absolute(local_point: Vector3) -> LkPosition64:
	return _origin.plus_local(local_point)

func to_local(absolute_point: LkPosition64) -> Vector3:
	return absolute_point.relative_to(_origin)

func register_root(root: Node3D) -> bool:
	if not is_instance_valid(root) or not root.is_inside_tree():
		return false
	if root is RigidBody3D:
		push_error("CoordinateFrame v1: RigidBody3D requires a dedicated physics adapter")
		return false
	for existing: Node3D in _roots:
		if not is_instance_valid(existing):
			continue
		if existing == root:
			return true
		if existing.is_ancestor_of(root) or root.is_ancestor_of(existing):
			push_error("CoordinateFrame: do not register both a parent and its child")
			return false
	_roots.append(root)
	return true

func unregister_root(root: Node3D) -> void:
	_roots.erase(root)

# Call explicitly at a coordinated physics boundary; no autonomous processing.
# Translation only: no changes to basis or velocity. No voxel/rigid-body adapters yet.
func maybe_shift(anchor_local: Vector3) -> bool:
	if anchor_local.length_squared() <= threshold_m * threshold_m:
		return false
	return shift_by(anchor_local)

# Origin shifts are snapped to a power-of-two grid coarser than the double
# resolution of the origin, so origin + delta is exact and a rebase loses nothing.
func _snap_to_origin_grid(delta: Vector3) -> Vector3:
	var largest: float = maxf(maxf(absf(_origin.x), absf(_origin.y)), maxf(absf(_origin.z), 1.0))
	var grid: float = pow(2.0, ceil(log(largest) / log(2.0)) - 51.0)
	return Vector3(roundf(delta.x / grid) * grid, roundf(delta.y / grid) * grid, roundf(delta.z / grid) * grid)


func shift_by(requested_delta: Vector3) -> bool:
	if not requested_delta.is_finite() or requested_delta.length_squared() <= 0.0:
		return false
	# This is rebasing, not interplanetary teleportation through a huge Vector3.
	if requested_delta.length() > 100000.0:
		push_error("CoordinateFrame: large relocation requires an absolute-position adapter")
		return false
	var local_delta: Vector3 = _snap_to_origin_grid(requested_delta)
	if local_delta.length_squared() <= 0.0:
		return false
	var live_roots: Array[Node3D] = []
	for root: Node3D in _roots:
		if is_instance_valid(root) and root.is_inside_tree():
			live_roots.append(root)
	_origin = _origin.plus_local(local_delta)
	_roots = live_roots
	for root: Node3D in _roots:
		var p: Vector3 = root.global_position
		root.global_position = Vector3(float(p.x) - float(local_delta.x), float(p.y) - float(local_delta.y), float(p.z) - float(local_delta.z))
		root.reset_physics_interpolation()
	shifted.emit(local_delta)
	return true
