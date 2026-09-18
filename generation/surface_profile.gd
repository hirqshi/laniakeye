@tool
class_name SurfaceProfile
extends Resource

enum TextureFilter {
	LINEAR,
	LINEAR_MIPMAP,
	NEAREST,
	NEAREST_MIPMAP,
}

enum TextureRepeat {
	REPEAT,
	CLAMP,
}

## Determines how PlanetMeshGenerator shapes terrain height for this
## profile. SIMPLEX gives smooth rolling hills, RIDGED gives sharp jagged
## mountain-ridge-like terrain (abs(noise) inverted, classic terrain trick).
enum TerrainNoiseType {
	SIMPLEX,
	RIDGED,
}

@export_category("identity")
@export var profile_name: String = "unnamed"

@export_category("pbr textures")
@export var albedo_texture: Texture2D
@export var normal_texture: Texture2D
@export var roughness_texture: Texture2D
@export var metallic_texture: Texture2D
@export var ao_texture: Texture2D
@export var height_texture: Texture2D
@export var emission_texture: Texture2D

@export_category("sampling")
@export var texture_filter: TextureFilter = TextureFilter.LINEAR_MIPMAP
@export var texture_repeat: TextureRepeat = TextureRepeat.REPEAT

@export_category("pbr values")
@export var roughness_value: float = 0.9
@export var roughness_multiplier: float = 1.0
@export var metallic_value: float = 0.0
@export var metallic_multiplier: float = 1.0
@export var ao_strength: float = 1.0
@export var normal_strength: float = 0.0
@export var emission_color: Color = Color.WHITE
@export var emission_energy: float = 0.0

@export_category("triplanar")
@export var triplanar_scale: float = 0.25
@export_range(1.0, 16.0, 0.1) var triplanar_blend_sharpness: float = 4.0
@export var triplanar_offset: Vector3 = Vector3.ZERO

@export_category("height detail")
@export var height_strength: float = 0.0
@export var use_height_parallax: bool = false

@export_category("procedural color")
@export var albedo_gradient: Gradient

@export_category("procedural vegetation")
@export var allow_vegetation: bool = false
@export var vegetation_density_min: float = 0.1
@export var vegetation_density_max: float = 0.6

@export_category("procedural terrain")
@export var terrain_noise_type: TerrainNoiseType = TerrainNoiseType.SIMPLEX
@export var terrain_noise_scale_min: float = 0.5
@export var terrain_noise_scale_max: float = 3.0
@export var terrain_height_min_m: float = 2.0
@export var terrain_height_max_m: float = 10.0

@export_category("procedural craters")
@export var allow_craters: bool = false
@export var crater_count_min: int = 3
@export var crater_count_max: int = 12
@export var crater_radius_min_ratio: float = 0.05
@export var crater_radius_max_ratio: float = 0.2
@export var crater_depth_m: float = 3.0
@export var crater_rim_height_m: float = 1.2

@export_category("procedural rings")
@export var allow_rings: bool = false
@export var ring_chance: float = 0.5
@export var ring_inner_radius_ratio_min: float = 1.5
@export var ring_inner_radius_ratio_max: float = 2.0
@export var ring_outer_radius_ratio_min: float = 2.5
@export var ring_outer_radius_ratio_max: float = 4.0
@export var ring_tilt_max_rad: float = 0.3
@export var ring_gradient: Gradient

@export_category("procedural atmosphere")
@export var has_atmosphere: bool = false
@export var atmosphere_outer_height_ratio: float = 0.08
@export var atmosphere_inner_height_ratio: float = 0.02
@export var atmosphere_rayleigh_color: Color = Color(0.29, 0.53, 1.0)
@export var atmosphere_mie_color: Color = Color(0.6, 0.6, 0.6)
@export var atmosphere_density: float = 1.0
@export var atmosphere_intensity: float = 6.0
@export var atmosphere_outer_edge_softness: float = 0.4
@export var atmosphere_surface_tint_strength: float = 0.3
@export var atmosphere_day_color: Color = Color(0.4, 0.7, 1.0)
@export var atmosphere_sunset_color: Color = Color(1.0, 0.5, 0.2)
@export var atmosphere_terminator_width: float = 0.3
@export var atmosphere_sunset_strength: float = 1.5

## an ocean is a spherical shell of water at sea_level_radius_ratio *
## radius_m. NOT restricted to the "ocean" preset - has_ocean can be
## turned on for any profile (e.g. a forest preset with small seas)
## since basin placement/coverage is controlled by the noise/threshold
## fields below, not by the preset identity itself.
@export_category("procedural ocean")
@export var has_ocean: bool = false
@export var sea_level_radius_ratio: float = 0.98
@export var ocean_basin_noise_scale: float = 1.5
@export var ocean_basin_threshold: float = 0.5
@export var ocean_basin_seed_offset: int = 900001
@export var ocean_basin_depth_m: float = 60.0
@export var ocean_basin_edge_softness: float = 0.05
@export var water_gradient: Gradient
@export var water_sky_color: Color = Color(0.5, 0.7, 0.9)
@export var water_surface_color: Color = Color(0.05, 0.25, 0.35)
@export var water_high_color: Color = Color(0.2, 0.5, 0.6)
@export var water_low_color: Color = Color(0.02, 0.1, 0.2)
@export var water_transmit_color: Color = Color(0.1, 0.3, 0.4)
@export var underwater_gravity_multiplier: float = 0.35
@export var underwater_speed_multiplier: float = 0.6
@export var depth_fade_distance_ratio: float = 0.4

@export_category("Vegetation")
@export var vegetation_profile: VegetationProfile

func should_generate_rings(rng: RandomNumberGenerator) -> bool:
	return allow_rings and rng.randf() <= ring_chance


func get_random_crater_count(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(crater_count_min, crater_count_max)


func get_random_albedo_color(rng: RandomNumberGenerator) -> Color:
	if albedo_gradient == null:
		return Color.WHITE
	return albedo_gradient.sample(rng.randf())


func get_random_vegetation_density(rng: RandomNumberGenerator) -> float:
	if not allow_vegetation:
		return 0.0
	return rng.randf_range(vegetation_density_min, vegetation_density_max)


func get_random_terrain_height(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(terrain_height_min_m, terrain_height_max_m)


func get_random_terrain_noise_scale(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(terrain_noise_scale_min, terrain_noise_scale_max)


func get_random_water_color(rng: RandomNumberGenerator) -> Color:
	if water_gradient == null:
		return water_surface_color
	return water_gradient.sample(rng.randf())
