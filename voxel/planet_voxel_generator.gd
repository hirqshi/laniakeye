class_name PlanetVoxelGenerator
extends VoxelGeneratorScript

@export var planet_radius_m: float = 6_371_000.0
@export var terrain_height_m: float = 4_000.0
@export var noise_seed: int = 0

var _noise: FastNoiseLite


func _init() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = noise_seed
	_noise.frequency = 0.3
	_noise.fractal_octaves = 4
	_noise.fractal_gain = 0.5
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	var buffer_size: Vector3i = out_buffer.get_size()
	var voxel_size_m: float = float(1 << lod)

	for x: int in range(buffer_size.x):
		for y: int in range(buffer_size.y):
			for z: int in range(buffer_size.z):
				var local: Vector3 = Vector3(float(x), float(y), float(z)) + Vector3.ONE * 0.5
				var world_pos: Vector3 = (
					Vector3(float(origin_in_voxels.x), float(origin_in_voxels.y), float(origin_in_voxels.z))
					+ local
				) * voxel_size_m

				var dx: float = world_pos.x
				var dy: float = world_pos.y
				var dz: float = world_pos.z
				var length: float = sqrt(dx * dx + dy * dy + dz * dz)
				if length < 0.0001:
					continue

				var direction: Vector3 = Vector3(dx / length, dy / length, dz / length)
				var surface_radius_m: float = _get_surface_radius(direction)
				var density_m: float = length - surface_radius_m
				var sdf: float = clampf(density_m / voxel_size_m, -1.0, 1.0)

				out_buffer.set_voxel_f(
					sdf,
					x,
					y,
					z,
					VoxelBuffer.CHANNEL_SDF
				)


func _get_surface_radius(direction: Vector3) -> float:
	var normalized_direction: Vector3 = direction.normalized()
	var noise_value: float = _noise.get_noise_3dv(normalized_direction * 100.0)
	return planet_radius_m + noise_value * terrain_height_m


func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_SDF
