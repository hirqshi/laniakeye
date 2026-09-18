class_name GravityBodyMath
extends RefCounted
## Static gravity-falloff and jump-scaling math shared by PlayerController
## and ShipController. Both computed the exact same inverse-falloff curve
## independently via a duck-typed call to gravity_source.get_radius() /
## get_gravity_zone_radius() - extracted here once now that it's genuinely
## used by two callers (per project convention: only abstract after two
## real use sites exist).
##
## Deliberately NOT a Node/component with state - both controllers already
## own their own gravity_mode/gravity_source/surface_gravity_strength
## fields tied into their movement code in ways that aren't worth
## re-plumbing right now. This just kills the duplicated formula.
##
## NOTE: player_controller.gd additionally multiplies the result by an
## underwater gravity multiplier when gravity_source.is_point_underwater()
## returns true - that wrapping stays in player_controller.gd, it's not
## part of the shared curve itself.


## Same inverse-falloff curve previously duplicated in player_controller.gd
## and ship_controller.gd's _get_falloff_gravity_strength(). gravity_source
## must respond to get_radius() and get_gravity_zone_radius() - if it
## doesn't, base_strength is returned unmodified (same fallback as the
## original duck-typed code).
static func get_falloff_gravity_strength(
	distance_to_center: float,
	surface_gravity_strength: float,
	gravity_multiplier: float,
	gravity_source: Node3D,
	gravity_fade_curve_power: float
) -> float:
	var base_strength: float = surface_gravity_strength * gravity_multiplier

	if not gravity_source.has_method("get_radius") or not gravity_source.has_method("get_gravity_zone_radius"):
		return base_strength

	var surface_radius: float = gravity_source.call("get_radius")
	var zone_radius: float = gravity_source.call("get_gravity_zone_radius")

	if distance_to_center <= surface_radius:
		return base_strength
	if distance_to_center >= zone_radius:
		return 0.0

	var zone_depth: float = zone_radius - surface_radius
	var distance_past_surface: float = distance_to_center - surface_radius
	var fade_ratio: float = 1.0 - clamp(distance_past_surface / zone_depth, 0.0, 1.0)
	return base_strength * pow(fade_ratio, gravity_fade_curve_power)


## Rescales jump launch velocity so jump HEIGHT stays roughly constant
## across planets with wildly different gravity_strength (moved from
## player_controller.gd verbatim, logic unchanged).
static func get_effective_jump_velocity(base_jump_velocity: float, gravity_strength: float) -> float:
	var reference_gravity: float = 9.8
	return base_jump_velocity * sqrt(max(gravity_strength, 0.1) / reference_gravity)
