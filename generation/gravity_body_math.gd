class_name GravityBodyMath
extends RefCounted
## Static gravity-falloff and jump-scaling math shared by PlayerController
## and ShipController. Both used to compute the exact same inverse-falloff
## curve independently - extracted here once, since it's now genuinely
## used by two callers (per project convention: only abstract after two
## real use sites exist).
##
## Deliberately NOT a Node/component with state - both controllers already
## own their own gravity_mode/gravity_source/surface_gravity_strength
## fields tied into their movement code in ways that aren't worth
## re-plumbing right now. This just kills the duplicated formula.


## Same inverse-falloff curve previously duplicated in player_controller.gd
## and ship_controller.gd's _get_falloff_gravity_strength(). distance_to_center
## is in meters from the gravity source's origin.
static func get_falloff_gravity_strength(
	distance_to_center: float,
	surface_gravity_strength: float,
	gravity_multiplier: float,
	planet_radius_m: float,
	gravity_zone_multiplier: float,
	gravity_fade_curve_power: float
) -> float:
	var base_strength: float = surface_gravity_strength * gravity_multiplier
	var zone_radius: float = planet_radius_m * gravity_zone_multiplier
	if zone_radius <= planet_radius_m:
		return base_strength
	var t: float = clamp((distance_to_center - planet_radius_m) / (zone_radius - planet_radius_m), 0.0, 1.0)
	var falloff: float = pow(1.0 - t, gravity_fade_curve_power)
	return base_strength * falloff


## Rescales jump launch velocity so jump HEIGHT stays roughly constant
## across planets with wildly different gravity_strength (moved from
## player_controller.gd verbatim, logic unchanged).
static func get_effective_jump_velocity(base_jump_velocity: float, gravity_strength: float) -> float:
	var reference_gravity: float = 9.8
	return base_jump_velocity * sqrt(max(gravity_strength, 0.1) / reference_gravity)
