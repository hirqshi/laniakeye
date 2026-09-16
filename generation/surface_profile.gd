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
@export var albedo_tint: Color = Color.WHITE
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

@export_category("procedural terrain")
@export var color_min: Color = Color.WHITE
@export var color_max: Color = Color.WHITE
@export var allow_vegetation: bool = false
@export var vegetation_density_min: float = 0.1
@export var vegetation_density_max: float = 0.6
@export var terrain_height_min_m: float = 2.0
@export var terrain_height_max_m: float = 10.0

func get_random_color(rng: RandomNumberGenerator) -> Color:
	return Color(
		rng.randf_range(color_min.r, color_max.r),
		rng.randf_range(color_min.g, color_max.g),
		rng.randf_range(color_min.b, color_max.b),
		1.0
	)

func get_random_vegetation_density(rng: RandomNumberGenerator) -> float:
	if not allow_vegetation:
		return 0.0

	return rng.randf_range(
		vegetation_density_min,
		vegetation_density_max
	)

func get_random_terrain_height(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(
		terrain_height_min_m,
		terrain_height_max_m
	)
