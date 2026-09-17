@tool
class_name PlanetData
extends Resource

## Pure data describing one planet or moon. No scene logic here.

@export var planet_seed: int = 0
@export var radius_m: float = 80.0
@export var gravity_strength: float = 9.8
@export var orbit_distance_m: float = 300.0
@export var orbit_angle_rad: float = 0.0
@export var orbit_speed_rad_s: float = 0.0
@export var axial_tilt_rad: float = 0.0
@export var rotation_speed_rad_s: float = 0.02

@export var surface_profile: Resource
@export var albedo_color: Color = Color.WHITE
@export var has_vegetation: bool = false
@export var vegetation_density: float = 0.0
@export var terrain_noise_scale: float = 1.0
@export var terrain_height_m: float = 5.0

@export var moons: Array[PlanetData] = []

@export var display_name: String = ""

func get_orbit_position(center: Vector3) -> Vector3:
	var offset: Vector3 = Vector3(
		cos(orbit_angle_rad) * orbit_distance_m,
		0.0,
		sin(orbit_angle_rad) * orbit_distance_m
	)
	return center + offset
