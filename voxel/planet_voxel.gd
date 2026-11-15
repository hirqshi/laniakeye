class_name PlanetVoxel
extends Node3D

@export var planet_radius_m: float = 6_371_000.0
@export var terrain_height_m: float = 4_000.0
@export var noise_seed: int = 0
@export var lod_count: int = 19
@export var view_distance_m: float = 160_000.0
@export var near_only_distance_m: float = 80_000.0
@export var transition_width_m: float = 40_000.0

var universe_position: UniversePosition
var _terrain: VoxelLodTerrain
var _far_mesh: PlanetFarMesh
var _effective_view_distance_m: float = 160_000.0
var _debug_timer_s: float = 10.0
var _debug_printed: bool = false


func _ready() -> void:
	universe_position = UniversePosition.new()
	_setup_terrain()
	call_deferred("_ensure_camera_range")


func _make_surface_material() -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec3 surface_color : source_color = vec3(0.35, 0.45, 0.3);
uniform vec3 direction_to_sun = vec3(0.353553, 0.707107, 0.612372);
uniform vec3 sunlight : source_color = vec3(1.2);
uniform vec3 ambient_light : source_color = vec3(0.09, 0.105, 0.135);
varying vec3 surface_world_normal;
void vertex() {
    surface_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    vec3 n = normalize(surface_world_normal);
    ALBEDO = surface_color * (ambient_light + sunlight * max(dot(n, normalize(direction_to_sun)), 0.0));
}
"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("surface_color", Vector3(0.35, 0.45, 0.3))
	return material


func _setup_terrain() -> void:
	var generator: PlanetVoxelGenerator = PlanetVoxelGenerator.new()
	generator.planet_radius_m = planet_radius_m
	generator.terrain_height_m = terrain_height_m
	generator.noise_seed = noise_seed
	var near_limit: float = maxf(near_only_distance_m, 1.0)
	var fade_width: float = maxf(transition_width_m, 1.0)
	var transition_end: float = near_limit + fade_width
	_effective_view_distance_m = maxf(view_distance_m, transition_end / 0.75)
	view_distance_m = _effective_view_distance_m
	var pot: int = 1024
	while planet_radius_m >= float(pot):
		pot *= 2
	var material: ShaderMaterial = _make_surface_material()
	_far_mesh = PlanetFarMesh.new()
	_far_mesh.planet_radius_m = planet_radius_m
	_far_mesh.terrain_height_m = terrain_height_m
	_far_mesh.noise_seed = noise_seed
	_far_mesh.far_min_distance_m = near_limit
	_far_mesh.far_fade_width_m = fade_width
	_far_mesh.blend_coverage_margin = transition_end / _effective_view_distance_m
	_far_mesh.blend_start_fraction = near_limit / transition_end
	add_child(_far_mesh)
	_terrain = VoxelLodTerrain.new()
	_terrain.lod_count = lod_count
	_terrain.lod_distance = 60
	_terrain.collision_lod_count = 2
	_terrain.generator = generator
	_terrain.view_distance = int(ceil(_effective_view_distance_m))
	_terrain.voxel_bounds = AABB(Vector3.ONE * -float(pot), Vector3.ONE * float(pot) * 2.0)
	_terrain.mesh_block_size = 32
	_terrain.mesher = VoxelMesherTransvoxel.new()
	_terrain.threaded_update_enabled = false
	_terrain.material = material
	add_child(_terrain)
	print("PlanetVoxel: near_only=%g m, transition_end=%g m, requested_view=%g m" % [near_limit, transition_end, _effective_view_distance_m])


func _ensure_camera_range() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		camera.far = maxf(camera.far, _effective_view_distance_m * 1.25)


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
