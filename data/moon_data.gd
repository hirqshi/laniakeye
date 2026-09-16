# moon_data.gd
class_name MoonData
extends Resource

@export var moon_seed: int = 0
@export var radius_m: float = 15.0
@export var gravity_strength: float = 2.0
@export var orbit_distance_m: float = 40.0
@export var orbit_angle_rad: float = 0.0
@export var orbit_speed_rad_s: float = 0.05
@export var rotation_speed_rad_s: float = 0.03
@export var albedo_color: Color = Color.GRAY
@export var terrain_noise_scale: float = 1.5
@export var terrain_height_m: float = 2.0

func get_orbit_position(planet_center: Vector3) -> Vector3:
	var offset: Vector3 = Vector3(
		cos(orbit_angle_rad) * orbit_distance_m,
		0.0,
		sin(orbit_angle_rad) * orbit_distance_m
	)
	return planet_center + offset
