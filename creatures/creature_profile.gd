@tool
class_name CreatureProfile
extends Resource

enum CreatureType { WORM, SQUID, SPIDER }

enum LocomotionMode { SURFACE_CLING, SURFACE_HOP, FLYING, SWIMMING }

@export var creature_type: CreatureType = CreatureType.WORM:
	set(value):
		creature_type = value
		_clamp_locomotion_mode()
		changed.emit()

@export_category("Locomotion")
@export var locomotion_mode: LocomotionMode = LocomotionMode.SURFACE_HOP:
	set(value):
		if not _is_locomotion_mode_valid(value):
			push_warning(
				"CreatureProfile: locomotion mode %d is not valid for creature_type %d, ignoring"
				% [value, creature_type]
			)
			return

		locomotion_mode = value
		changed.emit()

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

@export_range(0.2, 200.0, 0.1, "suffix:m")
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

@export_category("Runtime")
@export var creature_scene: PackedScene

@export_category("Worm Hop")

@export_range(0.1, 30.0, 0.1, "suffix:s")
var hop_interval_min_s: float = 2.0:
	set(value):
		hop_interval_min_s = value
		changed.emit()

@export_range(0.1, 30.0, 0.1, "suffix:s")
var hop_interval_max_s: float = 5.0:
	set(value):
		hop_interval_max_s = value
		changed.emit()

@export_range(0.5, 20.0, 0.1, "suffix:m/s")
var hop_launch_speed_mps: float = 6.0:
	set(value):
		hop_launch_speed_mps = value
		changed.emit()

@export_range(0.5, 20.0, 0.1, "suffix:m/s")
var hop_horizontal_speed_mps: float = 5.0:
	set(value):
		hop_horizontal_speed_mps = value
		changed.emit()

@export_range(0.1, 10.0, 0.01, "suffix:rad/s")
var hop_arc_turn_rate_rad_s: float = 2.5

@export_category("Worm Burrow")

@export_range(0.1, 10.0, 0.01, "suffix:m")
var burrow_depth_m: float = 0.5:
	set(value):
		burrow_depth_m = value
		changed.emit()

@export_range(0.1, 30.0, 0.01, "suffix:m/s")
var burrow_speed_mps: float = 3.0:
	set(value):
		burrow_speed_mps = value
		changed.emit()

@export_range(0.0, 20.0, 0.01, "suffix:m/s")
var burrow_turn_speed_rad_s: float = 0.65:
	set(value):
		burrow_turn_speed_rad_s = value
		changed.emit()
		
@export_range(0.0, 1.0, 0.01)
var hop_direction_reroll_chance: float = 0.35

@export_range(0.0, 3.14159, 0.01, "suffix:rad")
var hop_direction_jitter_rad: float = 1.2

@export_category("Flying")

@export_range(1.0, 500.0, 1.0, "suffix:m")
var flight_altitude_m: float = 40.0

@export_range(0.0, 100.0, 1.0, "suffix:m")
var flight_altitude_variation_m: float = 8.0

@export_range(0.01, 5.0, 0.01, "suffix:m/s")
var flight_altitude_change_speed: float = 0.15

@export_range(0.1, 50.0, 0.1, "suffix:m/s")
var flight_speed_mps: float = 6.0

@export_range(0.5, 60.0, 0.5, "suffix:s")
var flight_turn_interval_min_s: float = 4.0

@export_range(0.5, 60.0, 0.5, "suffix:s")
var flight_turn_interval_max_s: float = 10.0

@export_range(0.5, 60.0, 0.5, "suffix:s")
var flight_altitude_interval_min_s: float = 3.0

@export_range(0.5, 60.0, 0.5, "suffix:s")
var flight_altitude_interval_max_s: float = 8.0

@export_range(0.1, 20.0, 0.1)
var flight_turn_smoothing_speed: float = 4.0

@export_category("Swimming")

@export_range(0.1, 50.0, 0.1, "suffix:m/s")
var swim_speed_mps: float = 4.0

@export_range(0.01, 5.0, 0.01, "suffix:m/s")
var swim_depth_change_speed: float = 0.2

@export_range(0.0, 1.0, 0.01)
var swim_preferred_depth_ratio: float = 0.5

@export_range(0.0, 100.0, 1.0, "suffix:m")
var swim_depth_variation_m: float = 6.0

@export_range(0.1, 20.0, 0.01, "suffix:m")
var swim_wall_margin_m: float = 1.5

@export_range(0.5, 60.0, 0.5, "suffix:s")
var swim_turn_interval_min_s: float = 3.0

@export_range(0.5, 60.0, 0.5, "suffix:s")
var swim_turn_interval_max_s: float = 8.0

@export_range(0.5, 60.0, 0.5, "suffix:s")
var swim_depth_interval_min_s: float = 3.0

@export_range(0.5, 60.0, 0.5, "suffix:s")
var swim_depth_interval_max_s: float = 8.0

@export_range(0.1, 20.0, 0.1)
var swim_turn_smoothing_speed: float = 4.0

@export_category("Spider Walk")

@export_range(0.1, 20.0, 0.1, "suffix:m/s")
var spider_walk_speed_mps: float = 1.5

@export_range(0.0, 5.0, 0.01, "suffix:rad/s")
var spider_walk_turn_speed_rad_s: float = 0.4

@export_range(0.5, 60.0, 0.5, "suffix:s")
var spider_walk_turn_interval_min_s: float = 2.0

@export_range(0.5, 60.0, 0.5, "suffix:s")
var spider_walk_turn_interval_max_s: float = 5.0

@export_range(0.0, 1.0, 0.01)
var spider_walk_direction_reroll_chance: float = 0.3

@export_range(0.0, 3.14159, 0.01, "suffix:rad")
var spider_walk_direction_jitter_rad: float = 1.0

@export_range(0.0, 2.0, 0.01, "suffix:m")
var spider_ground_sink_m: float = 0.3

@export_range(0.1, 20.0, 0.1)
var spider_turn_smoothing_speed: float = 4.0

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

func get_valid_locomotion_modes() -> Array[LocomotionMode]:
	match creature_type:
		CreatureType.WORM:
			return [
				LocomotionMode.SURFACE_HOP,
				LocomotionMode.SWIMMING,
				LocomotionMode.FLYING
			]
		CreatureType.SQUID:
			return [
				LocomotionMode.SWIMMING,
				LocomotionMode.FLYING
			]
		CreatureType.SPIDER:
			return [LocomotionMode.SURFACE_CLING]

	return []

func _is_locomotion_mode_valid(mode: LocomotionMode) -> bool:
	return get_valid_locomotion_modes().has(mode)

func _clamp_locomotion_mode() -> void:
	if _is_locomotion_mode_valid(locomotion_mode):
		return

	var valid_modes: Array[LocomotionMode] = get_valid_locomotion_modes()
	if valid_modes.is_empty():
		return

	locomotion_mode = valid_modes[0]
