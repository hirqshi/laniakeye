class_name PlanetMeshGenerator
extends RefCounted

## Builds an icosphere and displaces every vertex through PlanetSurfaceSampler.
## Terrain, craters and ocean basins must be sampled through the same source
## so vegetation, collision and visible terrain cannot diverge.

const SUBDIVISIONS: int = 4

var _icosphere_indices: PackedInt32Array = PackedInt32Array()
var _surface_sampler: PlanetSurfaceSampler = PlanetSurfaceSampler.new()

func generate(
	radius_m: float,
	mesh_seed: int,
	noise_scale: float,
	height_m: float,
	noise_type: int = 0,
	surface_profile: Resource = null
) -> ArrayMesh:
	_surface_sampler.setup(
		radius_m,
		mesh_seed,
		noise_scale,
		height_m,
		noise_type,
		surface_profile
	)

	var vertices: PackedVector3Array = _build_icosphere(SUBDIVISIONS)

	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var displaced_vertices: PackedVector3Array = PackedVector3Array()
	displaced_vertices.resize(vertices.size())

	for vertex_index: int in range(vertices.size()):
		var direction: Vector3 = vertices[vertex_index].normalized()
		displaced_vertices[vertex_index] = _surface_sampler.get_surface_position(direction)

	for index_offset: int in range(0, _icosphere_indices.size(), 3):
		var index_a: int = _icosphere_indices[index_offset]
		var index_b: int = _icosphere_indices[index_offset + 1]
		var index_c: int = _icosphere_indices[index_offset + 2]

		var vertex_a: Vector3 = displaced_vertices[index_a]
		var vertex_b: Vector3 = displaced_vertices[index_b]
		var vertex_c: Vector3 = displaced_vertices[index_c]

		var uv_a: Vector2 = _direction_to_uv(vertex_a.normalized())
		var uv_b: Vector2 = _direction_to_uv(vertex_b.normalized())
		var uv_c: Vector2 = _direction_to_uv(vertex_c.normalized())

		var min_u: float = minf(uv_a.x, minf(uv_b.x, uv_c.x))
		var max_u: float = maxf(uv_a.x, maxf(uv_b.x, uv_c.x))

		if max_u - min_u > 0.5:
			if uv_a.x < 0.5:
				uv_a.x += 1.0

			if uv_b.x < 0.5:
				uv_b.x += 1.0

			if uv_c.x < 0.5:
				uv_c.x += 1.0

		surface_tool.set_uv(uv_a)
		surface_tool.add_vertex(vertex_a)

		surface_tool.set_uv(uv_b)
		surface_tool.add_vertex(vertex_b)

		surface_tool.set_uv(uv_c)
		surface_tool.add_vertex(vertex_c)

	surface_tool.generate_normals()
	surface_tool.generate_tangents()

	return surface_tool.commit()

func _fix_uv_seam(
	uv_a: Vector2,
	uv_b: Vector2,
	uv_c: Vector2
) -> void:
	var min_u: float = minf(uv_a.x, minf(uv_b.x, uv_c.x))
	var max_u: float = maxf(uv_a.x, maxf(uv_b.x, uv_c.x))

	if max_u - min_u <= 0.5:
		return

	if uv_a.x < 0.5:
		uv_a.x += 1.0

	if uv_b.x < 0.5:
		uv_b.x += 1.0

	if uv_c.x < 0.5:
		uv_c.x += 1.0

func _build_icosphere(subdivisions: int) -> PackedVector3Array:
	var golden_ratio: float = (1.0 + sqrt(5.0)) * 0.5

	var vertices: Array[Vector3] = [
		Vector3(-1.0, golden_ratio, 0.0),
		Vector3(1.0, golden_ratio, 0.0),
		Vector3(-1.0, -golden_ratio, 0.0),
		Vector3(1.0, -golden_ratio, 0.0),
		Vector3(0.0, -1.0, golden_ratio),
		Vector3(0.0, 1.0, golden_ratio),
		Vector3(0.0, -1.0, -golden_ratio),
		Vector3(0.0, 1.0, -golden_ratio),
		Vector3(golden_ratio, 0.0, -1.0),
		Vector3(golden_ratio, 0.0, 1.0),
		Vector3(-golden_ratio, 0.0, -1.0),
		Vector3(-golden_ratio, 0.0, 1.0)
	]

	for vertex_index: int in range(vertices.size()):
		vertices[vertex_index] = vertices[vertex_index].normalized()

	# Godot's front faces use clockwise winding.
	var faces: Array[Vector3i] = [
		Vector3i(0, 5, 11),
		Vector3i(0, 1, 5),
		Vector3i(0, 7, 1),
		Vector3i(0, 10, 7),
		Vector3i(0, 11, 10),
		Vector3i(1, 9, 5),
		Vector3i(5, 4, 11),
		Vector3i(11, 2, 10),
		Vector3i(10, 6, 7),
		Vector3i(7, 8, 1),
		Vector3i(3, 4, 9),
		Vector3i(3, 2, 4),
		Vector3i(3, 6, 2),
		Vector3i(3, 8, 6),
		Vector3i(3, 9, 8),
		Vector3i(4, 5, 9),
		Vector3i(2, 11, 4),
		Vector3i(6, 10, 2),
		Vector3i(8, 7, 6),
		Vector3i(9, 1, 8)
	]

	for subdivision_index: int in range(subdivisions):
		var new_faces: Array[Vector3i] = []
		var midpoint_cache: Dictionary[int, int] = {}

		for face: Vector3i in faces:
			var index_a: int = face.x
			var index_b: int = face.y
			var index_c: int = face.z

			var index_ab: int = _get_midpoint(
				index_a,
				index_b,
				vertices,
				midpoint_cache
			)
			var index_bc: int = _get_midpoint(
				index_b,
				index_c,
				vertices,
				midpoint_cache
			)
			var index_ca: int = _get_midpoint(
				index_c,
				index_a,
				vertices,
				midpoint_cache
			)

			new_faces.append(Vector3i(index_a, index_ab, index_ca))
			new_faces.append(Vector3i(index_b, index_bc, index_ab))
			new_faces.append(Vector3i(index_c, index_ca, index_bc))
			new_faces.append(Vector3i(index_ab, index_bc, index_ca))

		faces = new_faces

	_icosphere_indices.clear()

	for face: Vector3i in faces:
		_icosphere_indices.append(face.x)
		_icosphere_indices.append(face.y)
		_icosphere_indices.append(face.z)

	var result: PackedVector3Array = PackedVector3Array()

	for vertex: Vector3 in vertices:
		result.append(vertex)

	return result

func _get_midpoint(
	index_a: int,
	index_b: int,
	vertices: Array[Vector3],
	cache: Dictionary[int, int]
) -> int:
	var key: int = _get_edge_cache_key(index_a, index_b)

	if cache.has(key):
		return cache[key]

	var midpoint: Vector3 = (
		vertices[index_a] + vertices[index_b]
	).normalized()

	vertices.append(midpoint)

	var midpoint_index: int = vertices.size() - 1
	cache[key] = midpoint_index

	return midpoint_index

func _get_edge_cache_key(index_a: int, index_b: int) -> int:
	var smaller_index: int = mini(index_a, index_b)
	var larger_index: int = maxi(index_a, index_b)

	return smaller_index * 100_000 + larger_index

func _direction_to_uv(direction: Vector3) -> Vector2:
	var u: float = 0.5 + atan2(direction.z, direction.x) / TAU
	var v: float = 0.5 - asin(direction.y) / PI

	return Vector2(u, v)
