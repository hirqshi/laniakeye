class_name GenerationSettings
extends Resource

## Every tunable number for system/planet generation lives here.
## Create a .tres asset (New Resource -> GenerationSettings), tweak values
## in the inspector, assign it to SystemGenerator/StarSystem. No more
## digging into code to change planet count, gravity strength, moon count.

@export_group("System")
@export var min_planets: int = 4
@export var max_planets: int = 9
@export var star_radius_m: float = 300.0
@export var star_surface_gap_m: float = 100.0
@export var min_orbit_distance_m: float = 250.0
@export var orbit_distance_step_m: float = 180.0
@export var orbit_distance_jitter_m: float = 60.0

@export_group("Planet Size")
@export var planet_radius_min_m: float = 40.0
@export var planet_radius_max_m: float = 140.0

@export_group("Gravity")
@export var planet_gravity_min: float = 3.0
@export var planet_gravity_max: float = 16.0
@export var moon_gravity_min: float = 0.5
@export var moon_gravity_max: float = 4.0
@export var gravity_zone_multiplier: float = 1.6
@export var gravity_fade_curve_power: float = 1.5

@export_group("Orbit & Rotation")
@export_range(0.0, 0.02, 0.00001) var orbit_speed_min: float = 0.0001
@export_range(0.0, 0.02, 0.00001) var orbit_speed_max: float = 0.0006
@export var rotation_speed_min: float = 0.01
@export var rotation_speed_max: float = 0.05
@export var axial_tilt_max_rad: float = 0.4
@export var orbit_surface_gap_m: float = 50.0
@export var moon_surface_gap_m: float = 15.0
@export var moon_orbit_step_radius_multiplier: float = 3.0
@export var moon_orbit_jitter_min_m: float = 10.0
@export var moon_orbit_jitter_max_m: float = 30.0

@export_group("Moons")
@export var moon_chance: float = 0.5
@export var max_moons_per_planet: int = 3
@export var moon_radius_ratio_max: float = 0.35
@export var moon_orbit_speed_min: float = 0.03
@export var moon_orbit_speed_max: float = 0.12
@export var moon_rotation_speed_min: float = 0.02
@export var moon_rotation_speed_max: float = 0.08

@export_group("Terrain")
@export var moon_terrain_noise_scale_min: float = 0.5
@export var moon_terrain_noise_scale_max: float = 2.0
