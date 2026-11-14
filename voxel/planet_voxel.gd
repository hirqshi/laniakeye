class_name PlanetVoxel
extends Node3D

@export var planet_radius_m: float = 6_371_000.0
@export var terrain_height_m: float = 4_000.0
@export var noise_seed: int = 0
@export var lod_count: int = 19
@export var view_distance_m: float = 20_000.0

var universe_position: UniversePosition
var _terrain: VoxelLodTerrain


func _ready() -> void:
	universe_position = UniversePosition.new()
	_setup_terrain()


func _setup_terrain() -> void:
	var generator: PlanetVoxelGenerator = PlanetVoxelGenerator.new()
	generator.planet_radius_m = planet_radius_m
	generator.terrain_height_m = terrain_height_m
	generator.noise_seed = noise_seed

	var pot: int = 1024
	while planet_radius_m >= float(pot):
		pot *= 2

	_terrain = VoxelLodTerrain.new()
	_terrain.lod_count = lod_count
	_terrain.lod_distance = 60.0
	_terrain.collision_lod_count = 2
	_terrain.generator = generator
	_terrain.view_distance = view_distance_m
	_terrain.voxel_bounds = AABB(
		Vector3.ONE * -float(pot),
		Vector3.ONE * float(pot) * 2.0
	)
	_terrain.mesh_block_size = 32
	_terrain.mesher = VoxelMesherTransvoxel.new()
	_terrain.threaded_update_enabled = true
	add_child(_terrain)


func get_terrain() -> VoxelLodTerrain:
	return _terrain
