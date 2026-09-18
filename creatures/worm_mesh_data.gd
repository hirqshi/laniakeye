class_name WormMeshData
extends RefCounted

var mesh: ArrayMesh
var length_m: float = 1.0
var base_radius_m: float = 0.1
var segment_count: int = 8
var radial_segment_count: int = 6
var ring_radii_m: PackedFloat32Array = PackedFloat32Array()
var color: Color = Color.WHITE

var vertices: PackedVector3Array = PackedVector3Array()
var normals: PackedVector3Array = PackedVector3Array()
var colors: PackedColorArray = PackedColorArray()
var uvs: PackedVector2Array = PackedVector2Array()
var indices: PackedInt32Array = PackedInt32Array()

func get_ring_vertex_index(
	ring_index: int,
	radial_index: int
) -> int:
	return ring_index * radial_segment_count + radial_index

func get_side_vertex_count() -> int:
	return (segment_count + 1) * radial_segment_count
