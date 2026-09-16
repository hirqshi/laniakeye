extends Area3D

## Gravity zone for walking around INSIDE the ship's hull (not the seat -
## this is for a player who is NOT piloting, just walking around the
## interior). Unlike planet gravity (which pulls toward a center point),
## ship interior gravity pulls toward the ship's local -Y axis, i.e.
## "down" relative to the ship's own orientation - so it still works
## correctly while the ship is flying/rotating in space.
##
## FIX: both entered and exited now go through GravityZoneSelector, which
## reevaluates ALL overlapping "planet_gravity_zone" members and picks the
## closest one - instead of this zone unilaterally forcing set_flat_gravity
## on entry or blindly forcing set_zero_g on exit. The old exit handler
## could incorrectly zero out gravity even while the body was still inside
## a DIFFERENT valid zone (e.g. a planet's gravity while standing near an
## open airlock during landing). Both signals are now deferred consistently
## (previously entered was immediate and exited was deferred, which could
## let a stale deferred exit stomp a fresher immediate entry - see
## GravityZoneSelector for details).

@export var ship_root: Node3D
@export var interior_gravity_strength: float = 9.8

func _ready() -> void:
	add_to_group("planet_gravity_zone")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if not _supports_gravity(body):
		return
	call_deferred("_reevaluate", body)

func _on_body_exited(body: Node3D) -> void:
	if not _supports_gravity(body):
		return
	call_deferred("_reevaluate", body)

func _reevaluate(body: Node3D) -> void:
	GravityZoneSelector.reevaluate(body)

func _supports_gravity(body: Node3D) -> bool:
	return body.has_method("set_planet_gravity") and body.has_method("set_zero_g")

## Identifies this zone's gravity root and how it applies gravity, for
## GravityZoneSelector's closest-zone comparison.
func get_gravity_root() -> Node3D:
	return ship_root

func apply_gravity_to(body: Node3D) -> void:
	body.call("set_flat_gravity", ship_root, interior_gravity_strength)

func get_radius() -> float:
	return 0.0

func get_gravity_zone_radius() -> float:
	return 999999.0
