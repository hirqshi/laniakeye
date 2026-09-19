@tool
class_name MoonSurfaceProfile
extends Resource

## Separate catalog entry type for moons, distinct from SurfaceProfile
## (planets). Moons are much smaller and tend toward cratered, airless,
## barren looks far more often than planets - a shared class would force
## moon presets to carry planet-only concerns (vegetation, oceans) that
## rarely apply and to fight over the same ratio/scale defaults tuned for
## much larger bodies.

enum TerrainNoiseType {
	SIMPLEX,
	RIDGED,
}

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
@export var profile_name: String = "unnamed moon"

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
@export var roughness_value: float = 0.95
@export var roughness_multiplier: float = 1.0
@export var metallic_value: float = 0.0
@export var metallic_multiplier: float = 1.0
@export var ao_strength: float = 1.0
@export var normal_strength: float = 0.0
@export var emission_color: Color = Color.WHITE
@export var emission_energy: float = 0.0

@export_category("triplanar")
@export var triplanar_scale: float = 0.4
@export_range(1.0, 16.0, 0.1) var triplanar_blend_sharpness: float = 4.0
@export var triplanar_offset: Vector3 = Vector3.ZERO

@export_category("height detail")
@export var height_strength: float = 0.0
@export var use_height_parallax: bool = false

@export_category("procedural color")
@export var albedo_gradient: Gradient

@export_category("procedural terrain")
## Moons are small - default noise scale range is intentionally higher
## frequency than SurfaceProfile's planet defaults, so a single "hill"
## doesn't cover half the moon's surface.
@export var terrain_noise_type: TerrainNoiseType = TerrainNoiseType.SIMPLEX
@export var terrain_noise_scale_min: float = 1.5
@export var terrain_noise_scale_max: float = 4.0
@export var terrain_height_min_m: float = 1.0
@export var terrain_height_max_m: float = 4.0

@export_category("procedural craters")
## Moons default to craters ENABLED and more frequent - barren cratered
## moons are the common case, unlike planets where it's the exception.
@export var allow_craters: bool = true
@export var crater_count_min: int = 6
@export var crater_count_max: int = 24
@export var crater_radius_min_ratio: float = 0.04
@export var crater_radius_max_ratio: float = 0.18
@export var crater_depth_m: float = 1.5
@export var crater_rim_height_m: float = 0.6

@export_category("Ambient Audio")
@export var ambient_loop: AudioStream
@export_range(-24.0, 6.0, 0.1) var ambient_loop_volume_db: float = -12.0

func get_random_albedo_color(rng: RandomNumberGenerator) -> Color:
	if albedo_gradient == null:
		return Color.WHITE
	return albedo_gradient.sample(rng.randf())

func get_random_terrain_height(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(terrain_height_min_m, terrain_height_max_m)

func get_random_terrain_noise_scale(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(terrain_noise_scale_min, terrain_noise_scale_max)

func get_random_crater_count(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(crater_count_min, crater_count_max)
