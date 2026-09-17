
class_name WaterMeshGenerator
extends RefCounted

## Builds simple sphere meshes for a planet's ocean: the water surface
## (at sea_level_radius_m) and a simplified floor sphere (at a smaller
## radius, no detailed noise displacement - the real terrain is already
## fully hidden under water on ocean-heavy presets, so spending polygons
## on a detailed seafloor nobody will ever see is wasted budget).
##
## the water mesh is a FULL sphere, not a partial one carved to match
## ocean basins - basin shape (where water is visible vs. land pokes
## through) is handled entirely in the water shader via a mask noise
## sample, not via mesh topology. this avoids any seam/UV issues that
## come from generating irregular partial-sphere geometry.
##
## returns SphereMesh (a PrimitiveMesh), NOT ArrayMesh - they're sibling
## subclasses of Mesh, not related by inheritance, so the return type
## here is the common Mesh base class.

func generate_sphere(radius_m: float) -> Mesh:
	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = radius_m
	sphere_mesh.height = radius_m * 2.0
	sphere_mesh.rings = 64
	sphere_mesh.radial_segments = 64
	return sphere_mesh
