extends Area3D

## Bridges a planet's GravityArea to any body that knows how to receive
## gravity (player, ship - anything implementing set_planet_gravity/
## set_zero_g/get_current_gravity_source).
##
## FIX: both entered and exited now go through GravityZoneSelector,
## deferred consistently. Previously body_entered called
## _apply_closest_gravity_source() immediately/synchronously while
## body_exited deferred it - if a body crossed zone boundaries quickly
## (e.g. repeatedly entering/exiting near an edge, or transitioning
## between overlapping zones), a stale deferred exit reevaluation could
## execute AFTER a fresher immediate entry and overwrite it with wrong or
## null gravity. Deferring both consistently preserves the actual order
## events fired in, regardless of which zone or signal type.

@export var planet_root: Node3D

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
	return planet_root

func apply_gravity_to(body: Node3D) -> void:
	body.call("set_planet_gravity", planet_root, planet_root.call("get_gravity_strength"))
