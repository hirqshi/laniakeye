@tool
class_name CreatureProfile
extends Resource

enum CreatureType { WORM, SQUID, SPIDER }

@export_category("Textures")
@export var albedo_texture: Texture2D:
	set(value):
		albedo_texture = value
		changed.emit()

@export var normal_texture: Texture2D:
	set(value):
		normal_texture = value
		changed.emit()

@export var roughness_texture: Texture2D:
	set(value):
		roughness_texture = value
		changed.emit()

@export_category("Identity")
@export var display_name: String = "Unnamed Creature":
	set(value):
		display_name = value
		changed.emit()

		
@export var creature_type: CreatureType = CreatureType.WORM:
	set(value):
		creature_type = value
		changed.emit()

@export var preview_seed: int = 12345:
	set(value):
		preview_seed = value
		changed.emit()

@export_category("Worm Wiggle")
@export_range(0.0, 10.0, 0.1) var wave_amplitude_ratio: float = 3.0:
	set(value):
		wave_amplitude_ratio = value
		changed.emit()

@export_range(0.0, 10.0, 0.1) var wave_frequency: float = 2.0:
	set(value):
		wave_frequency = value
		changed.emit()

@export_range(-10.0, 10.0, 0.1) var wave_speed: float = 3.5:
	set(value):
		wave_speed = value
		changed.emit()
		
@export_category("Scale")
@export_range(0.2, 500.0, 0.1, "suffix:m")
var min_length_m: float = 1.5:
	set(value):
		min_length_m = value
		changed.emit()

@export_range(0.2, 500.0, 0.1, "suffix:m")
var max_length_m: float = 3.0:
	set(value):
		max_length_m = value
		changed.emit()

@export_category("Color")
@export var color_gradient: Gradient:
	set(value):
		color_gradient = value
		changed.emit()

@export_category("Worm Shape")
@export_range(4, 64, 1) var worm_segments: int = 20:
	set(value):
		worm_segments = value
		changed.emit()

@export_range(6, 16, 1) var worm_radial_segments: int = 8:
	set(value):
		worm_radial_segments = value
		changed.emit()

@export_range(0.02, 5.0, 0.01, "suffix:m")
var min_worm_radius_m: float = 0.15:
	set(value):
		min_worm_radius_m = value
		changed.emit()

@export_range(0.02, 5.0, 0.01, "suffix:m")
var max_worm_radius_m: float = 0.3:
	set(value):
		max_worm_radius_m = value
		changed.emit()

@export_category("Squid Shape")
@export_range(4, 12, 1) var tentacle_count: int = 6:
	set(value):
		tentacle_count = value
		changed.emit()

@export_range(0.2, 20.0, 0.1, "suffix:m")
var min_tentacle_length_m: float = 0.8:
	set(value):
		min_tentacle_length_m = value
		changed.emit()

@export_range(0.2, 20.0, 0.1, "suffix:m")
var max_tentacle_length_m: float = 1.6:
	set(value):
		max_tentacle_length_m = value
		changed.emit()

@export_range(6, 16, 1) var tentacle_segments: int = 8:
	set(value):
		tentacle_segments = value
		changed.emit()

@export_category("Squid Body")
@export_range(0.1, 100.0, 0.1, "suffix:m")
var squid_body_length_ratio: float = 0.55:
	set(value):
		squid_body_length_ratio = value
		changed.emit()

@export_range(0.1, 5.0, 0.01)
var squid_body_radius_ratio: float = 0.35:
	set(value):
		squid_body_radius_ratio = value
		changed.emit()

@export_range(4, 32, 1)
var squid_body_rings: int = 10:
	set(value):
		squid_body_rings = value
		changed.emit()

@export_range(6, 24, 1)
var squid_body_radial_segments: int = 10:
	set(value):
		squid_body_radial_segments = value
		changed.emit()

@export_category("Squid Tentacles")
@export_range(0.01, 5.0, 0.01, "suffix:m")
var tentacle_radius_ratio: float = 0.12:
	set(value):
		tentacle_radius_ratio = value
		changed.emit()

@export_range(0.0, 1.0, 0.01)
var tentacle_taper: float = 0.75:
	set(value):
		tentacle_taper = value
		changed.emit()

@export_range(3, 16, 1)
var tentacle_radial_segments: int = 5:
	set(value):
		tentacle_radial_segments = value
		changed.emit()

@export_category("Squid Body Motion")
@export_range(0.0, 1.0, 0.01)
var squid_body_wiggle_multiplier: float = 0.12:
	set(value):
		squid_body_wiggle_multiplier = value
		changed.emit()

@export_range(0.0, 1.0, 0.01)
var tentacle_attachment_inset_ratio: float = 0.35:
	set(value):
		tentacle_attachment_inset_ratio = value
		changed.emit()
		
@export_category("Squid Tentacle Motion")
@export_range(0.0, 10.0, 0.1)
var tentacle_wave_frequency: float = 1.4:
	set(value):
		tentacle_wave_frequency = value
		changed.emit()

@export_range(-10.0, 10.0, 0.1)
var tentacle_wave_speed: float = 2.0:
	set(value):
		tentacle_wave_speed = value
		changed.emit()

@export_range(0.0, 10.0, 0.1)
var tentacle_wave_amplitude_ratio: float = 1.2:
	set(value):
		tentacle_wave_amplitude_ratio = value
		changed.emit()
		
@export_range(0.0, 1.0, 0.01)
var tentacle_length_variation: float = 0.35:
	set(value):
		tentacle_length_variation = value
		changed.emit()

@export_range(0.0, 1.0, 0.01)
var tentacle_radius_variation: float = 0.25:
	set(value):
		tentacle_radius_variation = value
		changed.emit()

@export_range(0.0, 1.0, 0.01)
var tentacle_angle_variation_rad: float = 0.35:
	set(value):
		tentacle_angle_variation_rad = value
		changed.emit()

@export_range(0.0, 0.8, 0.01)
var tentacle_missing_chance: float = 0.12:
	set(value):
		tentacle_missing_chance = value
		changed.emit()

@export_category("Spider Shape")
@export_range(4, 8, 1) var min_leg_count: int = 4:
	set(value):
		min_leg_count = value
		changed.emit()

@export_range(4, 8, 1) var max_leg_count: int = 8:
	set(value):
		max_leg_count = value
		changed.emit()

@export_range(0.1, 5.0, 0.01, "suffix:m")
var min_leg_length_m: float = 0.5:
	set(value):
		min_leg_length_m = value
		changed.emit()

@export_range(0.1, 5.0, 0.01, "suffix:m")
var max_leg_length_m: float = 0.9:
	set(value):
		max_leg_length_m = value
		changed.emit()

@export_range(0.05, 2.0, 0.005, "suffix:m")
var spider_body_radius_m: float = 0.4:
	set(value):
		spider_body_radius_m = value
		changed.emit()

@export_range(0.01, 1.0, 0.005, "suffix:m")
var spider_leg_radius_m: float = 0.055:
	set(value):
		spider_leg_radius_m = value
		changed.emit()

@export_range(0.0, 1.0, 0.01)
var spider_leg_bend: float = 0.55:
	set(value):
		spider_leg_bend = value
		changed.emit()
		
@export_range(0.05, 1.0, 0.01)
var spider_body_radius_ratio: float = 0.22:
	set(value):
		spider_body_radius_ratio = value
		changed.emit()
		
@export_category("Spider Motion")
@export_range(0.0, 30.0, 0.01, "suffix:deg")
var spider_idle_step_amplitude_deg: float = 6.0:
	set(value):
		spider_idle_step_amplitude_deg = value
		changed.emit()

@export_range(0.0, 10.0, 0.01)
var spider_idle_step_speed: float = 2.0:
	set(value):
		spider_idle_step_speed = value
		changed.emit()

func get_length_m(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(min_length_m, max_length_m)

func get_worm_radius_m(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(min_worm_radius_m, max_worm_radius_m)

func get_tentacle_length_m(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(min_tentacle_length_m, max_tentacle_length_m)

func get_leg_count(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(min_leg_count, max_leg_count)

func get_leg_length_m(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(min_leg_length_m, max_leg_length_m)

func get_color(rng: RandomNumberGenerator) -> Color:
	if color_gradient == null:
		return Color.WHITE
	return color_gradient.sample(rng.randf())
