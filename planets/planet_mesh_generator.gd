class_name PlanetMeshGenerator
extends RefCounted

## Builds an icosphere via subdivision, displaces vertices with noise,
## optionally stamps craters as a second deformation pass, returns a ready
## ArrayMesh. Not thread-safe (uses instance state, safe as long as you
## generate one planet mesh at a time on the main thread).
##
## CRATERS: a second, separate deformation pass applied AFTER the base
## terrain noise. For each vertex, find the closest crater center (angular
## distance on the sphere, not straight-line, since vertices live on a
## sphere surface) and if within that crater's angular radius, apply a
## bowl+rim profile on top of the already-displaced radius. Craters are
## discrete, placed, countable objects with a controlled shape - not part
## of the continuous noise function.
##
## Each crater's angular radius is computed ONCE at generation time
## (crater_radius_m / planet_radius_m, as a small-angle approximation of
## arc length) and stored directly in its dictionary - no reconstruction
## or guessing needed later in the hot per-vertex sampling loop.
##
## NOTE on winding order: Godot uses CLOCKWISE winding for front faces
## (unlike OpenGL's CCW default) - see godot-docs issue #10757. The base
## icosahedron face list below is written with indices swapped (a, c, b
## instead of a, b, c) specifically to produce CW winding when viewed
## from outside the sphere, so generate_normals() computes outward-facing
## normals instead of inverted ones.

const SUBDIVISIONS: int = 4
const CRATER_RIM_POSITION: float = 0.85
const CRATER_RIM_WIDTH: float = 0.08

var _icosphere_indices: PackedInt32Array = PackedInt32Array()

func generate(
	radius_m: float,
	mesh_seed: int,
	noise_scale: float,
	height_m: float,
	noise_type: int = 0,
	crater_profile: Resource = null
) -> ArrayMesh:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = mesh_seed
	noise.frequency = 0.01 * noise_scale
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.5

	if noise_type == 1:  # RIDGED - same ordinal in both SurfaceProfile and MoonSurfaceProfile enums
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	else:
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM

	var vertices: PackedVector3Array = _build_icosphere(SUBDIVISIONS)

	var craters: Array[Dictionary] = []
	if crater_profile != null and crater_profile.get("allow_craters"):
		craters = _generate_craters(crater_profile, mesh_seed, radius_m)

	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var displaced: PackedVector3Array = PackedVector3Array()
	displaced.resize(vertices.size())

	for i in range(vertices.size()):
		var direction: Vector3 = vertices[i].normalized()
		var noise_value: float = noise.get_noise_3dv(direction * 100.0)
		var displaced_radius: float = radius_m + noise_value * height_m

		if not craters.is_empty():
			displaced_radius += _sample_craters(direction, craters)

		displaced[i] = direction * displaced_radius

	for i in range(0, _icosphere_indices.size(), 3):
		var idx0: int = _icosphere_indices[i]
		var idx1: int = _icosphere_indices[i + 1]
		var idx2: int = _icosphere_indices[i + 2]

		var v0: Vector3 = displaced[idx0]
		var v1: Vector3 = displaced[idx1]
		var v2: Vector3 = displaced[idx2]

		var uv0: Vector2 = _direction_to_uv(v0.normalized())
		var uv1: Vector2 = _direction_to_uv(v1.normalized())
		var uv2: Vector2 = _direction_to_uv(v2.normalized())

		# seam fix: if this triangle straddles the U=0/U=1 wraparound
		# (any pair of its UVs differs by more than half the UV range),
		# push the LOW-side U values up by 1.0 so all three UVs are
		# continuous across this specific triangle - avoids the GPU
		# interpolating "the wrong way around" through 0..1.
		var max_u: float = max(uv0.x, max(uv1.x, uv2.x))
		if max_u - min(uv0.x, min(uv1.x, uv2.x)) > 0.5:
			if uv0.x < 0.5:
				uv0.x += 1.0
			if uv1.x < 0.5:
				uv1.x += 1.0
			if uv2.x < 0.5:
				uv2.x += 1.0

		surface_tool.set_uv(uv0)
		surface_tool.add_vertex(v0)
		surface_tool.set_uv(uv1)
		surface_tool.add_vertex(v1)
		surface_tool.set_uv(uv2)
		surface_tool.add_vertex(v2)

	surface_tool.generate_normals()
	surface_tool.generate_tangents()

	return surface_tool.commit()

## Picks crater_count random points on the unit sphere as crater centers,
## each with its own random linear radius (radius_m * ratio range),
## converted ONCE to an angular radius here - all derived from mesh_seed
## so the same planet always gets the same craters.
func _generate_craters(profile: Resource, mesh_seed: int, planet_radius_m: float) -> Array[Dictionary]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = mesh_seed + 987654

	var count: int = profile.call("get_random_crater_count", rng)
	var craters: Array[Dictionary] = []

	for i in range(count):
		var center: Vector3 = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		)
		if center.length_squared() < 0.0001:
			center = Vector3.UP
		center = center.normalized()

		var radius_ratio: float = rng.randf_range(profile.get("crater_radius_min_ratio"), profile.get("crater_radius_max_ratio"))
		var crater_radius_m: float = planet_radius_m * radius_ratio
		var angular_radius_rad: float = crater_radius_m / max(planet_radius_m, 0.001)

		craters.append({
			"center": center,
			"angular_radius_rad": angular_radius_rad,
			"depth_m": profile.get("crater_depth_m"),
			"rim_height_m": profile.get("crater_rim_height_m"),
		})

	return craters

## Applies the closest crater's bowl+rim profile to a vertex, given its
## direction from the sphere center. Only the CLOSEST crater affects each
## vertex - overlapping craters don't stack, matching how real crater
## fields look (newer craters simply erase/dominate older overlapping ones).
func _sample_craters(direction: Vector3, craters: Array[Dictionary]) -> float:
	var best_offset: float = 0.0
	var best_angular_dist: float = INF

	for crater in craters:
		var center: Vector3 = crater["center"]
		var cos_angle: float = clamp(direction.dot(center), -1.0, 1.0)
		var angular_dist_rad: float = acos(cos_angle)

		if angular_dist_rad >= best_angular_dist:
			continue
		if angular_dist_rad > crater["angular_radius_rad"]:
			continue

		best_angular_dist = angular_dist_rad
		best_offset = _crater_bowl_profile(angular_dist_rad, crater)

	return best_offset

func _crater_bowl_profile(angular_dist_rad: float, crater: Dictionary) -> float:
	var angular_radius_rad: float = crater["angular_radius_rad"]
	var depth_m: float = crater["depth_m"]
	var rim_height_m: float = crater["rim_height_m"]

	var t: float = angular_dist_rad / max(angular_radius_rad, 0.0001)

	var bowl: float = (t * t - 1.0) * depth_m
	var rim: float = exp(-pow(t - CRATER_RIM_POSITION, 2.0) / (2.0 * CRATER_RIM_WIDTH * CRATER_RIM_WIDTH)) * rim_height_m

	return bowl + rim

func _build_icosphere(subdivisions: int) -> PackedVector3Array:
	var t: float = (1.0 + sqrt(5.0)) / 2.0
	var vertices: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)
	]
	for i in range(vertices.size()):
		vertices[i] = vertices[i].normalized()

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
