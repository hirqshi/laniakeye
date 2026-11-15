class_name LkVoxelOriginAdapter
extends RefCounted

# Keeps voxel sampling/editing tied to ABSOLUTE coordinates while the terrain
# Node3D is rebased with the local scene. The terrain node itself is a local
# rendering/collision representation; voxel addresses must not drift with it.

var coordinate_frame: LkCoordinateFrame
var terrain: VoxelLodTerrain
var terrain_anchor_absolute: LkPosition64
var edits: Dictionary = {}

func _init(frame: LkCoordinateFrame, target_terrain: VoxelLodTerrain, anchor_absolute: LkPosition64) -> void:
	coordinate_frame = frame
	terrain = target_terrain
	terrain_anchor_absolute = anchor_absolute.copy()

func absolute_to_voxel(absolute_point: LkPosition64) -> Vector3i:
	# Convert the large absolute position to a normal local Vector3 first.
	# Then convert that local Vector3 into terrain-local space. Do not add the
	# frame origin again: that would create an astronomically large coordinate
	# and overflow Vector3i.
	var local: Vector3 = coordinate_frame.to_local(absolute_point)
	var terrain_local: Vector3 = terrain.to_local(local)
	return Vector3i(terrain_local.floor())

func voxel_to_absolute(voxel: Vector3i) -> LkPosition64:
	var terrain_local: Vector3 = Vector3(voxel) + Vector3(0.5, 0.5, 0.5)
	var world_local: Vector3 = terrain.to_global(terrain_local)
	return coordinate_frame.to_absolute(world_local)

func record_edit(absolute_point: LkPosition64, radius_m: float, remove_material: bool) -> int:
	var center_voxel: Vector3i = absolute_to_voxel(absolute_point)
	var key: String = "%d:%d:%d:%s" % [center_voxel.x, center_voxel.y, center_voxel.z, "remove" if remove_material else "add"]
	if not edits.has(key):
		edits[key] = {"center": center_voxel, "radius": radius_m, "remove": remove_material}
	return edits.size()

func edit_count() -> int:
	return edits.size()

func has_edit_near(absolute_point: LkPosition64, max_distance_m: float) -> bool:
	for edit: Dictionary in edits.values():
		var edit_absolute: LkPosition64 = voxel_to_absolute(edit["center"])
		if edit_absolute.minus(absolute_point).length() <= max_distance_m:
			return true
	return false
