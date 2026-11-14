class_name PlanetVoxel
extends Node3D

@export var planet_radius_m: float = 6_371_000.0
@export var terrain_height_m: float = 4_000.0
@export var noise_seed: int = 0
@export var lod_count: int = 19
@export var view_distance_m: float = 20_000.0

var universe_position: UniversePosition
var _terrain: VoxelLodTerrain
var _far_mesh: PlanetFarMesh
var _debug_timer_s: float = 10.0
var _debug_printed: bool = false


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

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.45, 0.3)
	material.roughness = 1.0

	_far_mesh = PlanetFarMesh.new()
	_far_mesh.planet_radius_m = planet_radius_m
	_far_mesh.terrain_height_m = terrain_height_m
	_far_mesh.noise_seed = noise_seed
	_far_mesh.material_override = material
	add_child(_far_mesh)

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
	_terrain.threaded_update_enabled = false
	_terrain.material = material
	add_child(_terrain)


func _process(delta: float) -> void:
	if _debug_printed:
		return
	_debug_timer_s -= delta
	if _debug_timer_s > 0.0:
		return
	_debug_printed = true
	_print_terrain_stats()


func _print_terrain_stats() -> void:
	if _terrain == null:
		print("PlanetVoxel: terrain is null")
		return

	var data_blocks: int = _terrain.debug_get_data_block_count()
	var mesh_blocks: int = _terrain.debug_get_mesh_block_count()
	print("PlanetVoxel: data_blocks=%d mesh_blocks=%d" % [data_blocks, mesh_blocks])

	var probe_position: Vector3 = Vector3(0.0, planet_radius_m + terrain_height_m + 100.0, 0.0)
	var voxel_tool: VoxelToolLodTerrain = _terrain.get_voxel_tool()
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	var sdf: float = voxel_tool.get_voxel_f_interpolated(probe_position)
	print("PlanetVoxel: sdf_at_probe=%f (negative = inside solid)" % sdf)


func get_terrain() -> VoxelLodTerrain:
	return _terrain


func get_far_mesh() -> PlanetFarMesh:
	return _far_mesh
