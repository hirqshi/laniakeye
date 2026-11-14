class_name PlanetFarMesh
extends MeshInstance3D

@export var planet_radius_m: float = 6_371_000.0
@export var terrain_height_m: float = 4_000.0
@export var noise_seed: int = 0
@export var segments: int = 256
@export var rings: int = 128


func _ready() -> void:
	mesh = _build_mesh()


func _build_mesh() -> ArrayMesh:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 0.3
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.5
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM

	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()

	for y: int in range(rings + 1):
		var v: float = float(y) / float(rings)
		var phi: float = v * PI
		for x: int in range(segments + 1):
			var u: float = float(x) / float(segments)
			var theta: float = u * TAU
			var dir: Vector3 = Vector3(
				sin(phi) * cos(theta),
				cos(phi),
				sin(phi) * sin(theta)
			)
			var n: float = noise.get_noise_3dv(dir * 100.0)
			var radius: float = planet_radius_m + n * terrain_height_m * 0.5
			verts.append(dir * radius)
			normals.append(dir)
			uvs.append(Vector2(u, v))

	for y: int in range(rings):
		for x: int in range(segments):
			var a: int = y * (segments + 1) + x
			var b: int = a + 1
			var c: int = a + (segments + 1)
			var d: int = c + 1
			indices.append(a)
			indices.append(b)
			indices.append(c)
			indices.append(b)
			indices.append(d)
			indices.append(c)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
