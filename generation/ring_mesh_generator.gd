class_name RingMeshGenerator
extends RefCounted

## Builds a flat ring disc mesh (annulus) - a circle with a hole in the
## middle, NOT a torus. A torus has volume/thickness that's wasted detail
## for something meant to look paper-thin from any reasonable viewing
## distance, like Saturn's rings.
##
## UV.x is tied to RADIAL POSITION, not triangle winding order: inner-edge
## vertices always get u=0, outer-edge vertices always get u=1, regardless
## of which corner of the triangle they end up in. This lets a 1D-style
## ring texture (or a Gradient sampled into a 1D texture) map cleanly
## across the ring's radial band - the shader/material reads UV.x to look
## up color/alpha per radius rather than per angle.

const SEGMENTS: int = 64
const INNER_U: float = 0.0
const OUTER_U: float = 1.0

func generate(inner_radius_m: float, outer_radius_m: float) -> ArrayMesh:
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var inner_points: PackedVector3Array = PackedVector3Array()
	var outer_points: PackedVector3Array = PackedVector3Array()

	for i in range(SEGMENTS + 1):
		var angle: float = TAU * float(i) / float(SEGMENTS)
		var dir: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		inner_points.append(dir * inner_radius_m)
		outer_points.append(dir * outer_radius_m)

	for i in range(SEGMENTS):
		var in0: Vector3 = inner_points[i]
		var in1: Vector3 = inner_points[i + 1]
		var out0: Vector3 = outer_points[i]
		var out1: Vector3 = outer_points[i + 1]

		# two triangles per segment forming one quad of the annulus band.
		# CW winding (Godot's front-face convention) viewed from above (+Y).
		_add_vertex(surface_tool, in0, INNER_U)
		_add_vertex(surface_tool, out0, OUTER_U)
		_add_vertex(surface_tool, out1, OUTER_U)

		_add_vertex(surface_tool, in0, INNER_U)
		_add_vertex(surface_tool, out1, OUTER_U)
		_add_vertex(surface_tool, in1, INNER_U)

	surface_tool.generate_normals()
	surface_tool.generate_tangents()

	return surface_tool.commit()

func _add_vertex(surface_tool: SurfaceTool, position: Vector3, u: float) -> void:
	surface_tool.set_uv(Vector2(u, 0.0))
	surface_tool.add_vertex(position)
