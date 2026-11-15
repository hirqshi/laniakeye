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

func shift_by(local_delta: Vector3) -> bool:
	if not local_delta.is_finite() or local_delta.length_squared() <= 0.0:
		return false
	# This is rebasing, not interplanetary teleportation through a huge Vector3.
	if local_delta.length() > 100000.0:
		push_error("CoordinateFrame: large relocation requires an absolute-position adapter")
		return false
	var live_roots: Array[Node3D] = []
	var absolute_positions: Array[LkPosition64] = []
	for root: Node3D in _roots:
		if is_instance_valid(root) and root.is_inside_tree():
			live_roots.append(root)
			absolute_positions.append(to_absolute(root.global_position))
	_origin = _origin.plus_local(local_delta)
	_roots = live_roots
	for i: int in range(_roots.size()):
		_roots[i].global_position = to_local(absolute_positions[i])
		_roots[i].reset_physics_interpolation()
	shifted.emit(local_delta)
	return true
