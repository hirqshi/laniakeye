class_name PlanetMeshGenerator
extends RefCounted

## Builds an icosphere via subdivision, displaces vertices with noise,
## returns a ready ArrayMesh. Not thread-safe (uses instance state, safe
## as long as you generate one planet mesh at a time on the main thread).
##
## NOTE on winding order: Godot uses CLOCKWISE winding for front faces
## (unlike OpenGL's CCW default) - see godot-docs issue #10757. The base
## icosahedron face list below is written with indices swapped (a, c, b
## instead of a, b, c) specifically to produce CW winding when viewed
## from outside the sphere, so generate_normals() computes outward-facing
## normals instead of inverted ones.

const SUBDIVISIONS: int = 4

var _icosphere_indices: PackedInt32Array = PackedInt32Array()

func generate(radius_m: float, mesh_seed: int, noise_scale: float, height_m: float) -> ArrayMesh:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = mesh_seed
	noise.frequency = 0.01 * noise_scale
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.5

	var vertices: PackedVector3Array = _build_icosphere(SUBDIVISIONS)

	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var displaced: PackedVector3Array = PackedVector3Array()
	displaced.resize(vertices.size())

	for i in range(vertices.size()):
		var direction: Vector3 = vertices[i].normalized()
		var noise_value: float = noise.get_noise_3dv(direction * 100.0)
		var displaced_radius: float = radius_m + noise_value * height_m
		displaced[i] = direction * displaced_radius

	for idx in _icosphere_indices:
		var vertex: Vector3 = displaced[idx]
		surface_tool.set_uv(_direction_to_uv(vertex.normalized()))
		surface_tool.add_vertex(vertex)

	surface_tool.generate_normals()
	surface_tool.generate_tangents()

	return surface_tool.commit()

func _build_icosphere(subdivisions: int) -> PackedVector3Array:
	var t: float = (1.0 + sqrt(5.0)) / 2.0
	var vertices: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)
	]
	for i in range(vertices.size()):
		vertices[i] = vertices[i].normalized()

	# faces defined as (a, c, b) instead of (a, b, c): flips winding to CW
	# as seen from outside the sphere, matching Godot's front-face convention.
	var faces: Array[Vector3i] = [
		Vector3i(0, 5, 11), Vector3i(0, 1, 5), Vector3i(0, 7, 1), Vector3i(0, 10, 7), Vector3i(0, 11, 10),
		Vector3i(1, 9, 5), Vector3i(5, 4, 11), Vector3i(11, 2, 10), Vector3i(10, 6, 7), Vector3i(7, 8, 1),
		Vector3i(3, 4, 9), Vector3i(3, 2, 4), Vector3i(3, 6, 2), Vector3i(3, 8, 6), Vector3i(3, 9, 8),
		Vector3i(4, 5, 9), Vector3i(2, 11, 4), Vector3i(6, 10, 2), Vector3i(8, 7, 6), Vector3i(9, 1, 8)
	]

	for _s in range(subdivisions):
		var new_faces: Array[Vector3i] = []
		var midpoint_cache: Dictionary = {}
		for face in faces:
			var a: int = face.x
			var b: int = face.y
			var c: int = face.z
			var ab: int = _get_midpoint(a, b, vertices, midpoint_cache)
			var bc: int = _get_midpoint(b, c, vertices, midpoint_cache)
			var ca: int = _get_midpoint(c, a, vertices, midpoint_cache)

			new_faces.append(Vector3i(a, ab, ca))
			new_faces.append(Vector3i(b, bc, ab))
			new_faces.append(Vector3i(c, ca, bc))
			new_faces.append(Vector3i(ab, bc, ca))

		faces = new_faces

	_icosphere_indices.clear()
	for face in faces:
		_icosphere_indices.append(face.x)
		_icosphere_indices.append(face.y)
		_icosphere_indices.append(face.z)

	var result: PackedVector3Array = PackedVector3Array()
	for v in vertices:
		result.append(v)
	return result

func _get_midpoint(i1: int, i2: int, vertices: Array[Vector3], cache: Dictionary) -> int:
	var key: int = _cache_key(i1, i2)
	if cache.has(key):
		return cache[key]

	var midpoint: Vector3 = ((vertices[i1] + vertices[i2]) * 0.5).normalized()
	vertices.append(midpoint)
	var new_index: int = vertices.size() - 1
	cache[key] = new_index
	return new_index

func _cache_key(i1: int, i2: int) -> int:
	var lo: int = min(i1, i2)
	var hi: int = max(i1, i2)
	return lo * 100000 + hi

func _direction_to_uv(direction: Vector3) -> Vector2:
	var u: float = 0.5 + atan2(direction.z, direction.x) / TAU
	var v: float = 0.5 - asin(direction.y) / PI
	return Vector2(u, v)
