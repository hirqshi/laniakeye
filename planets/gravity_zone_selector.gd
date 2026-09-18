class_name GravityZoneSelector
extends RefCounted

## Shared logic for picking which gravity zone a body should currently
## belong to, used by BOTH the ship interior zone and the planet exterior
## zone. Any GravityZone in the "planet_gravity_zone" group participates.
##
## Both entered and exited handlers on participating zones should call
## this via call_deferred, consistently, so relative event ordering is
## preserved and a stale reevaluation from one zone can't stomp a fresher
## one from another.
##
## REFACTOR: zones are now looked up as GravityZone (typed) instead of
## Area3D + has_method()/call() by string. A malformed/renamed method on
## a zone script now fails at parse time instead of silently falling back
## to priority 0 or doing nothing.

static func reevaluate(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	if not body.is_inside_tree():
		return
	if not body.has_method("set_zero_g"):
		return

	var best_zone: GravityZone = null
	var best_priority: int = -1
	var best_distance: float = INF

	for area in body.get_tree().get_nodes_in_group("planet_gravity_zone"):
		var zone: GravityZone = area as GravityZone
		if zone == null:
			continue
		if not zone.overlaps_body(body):
			continue

		var candidate_root: Node3D = zone.get_gravity_root()
		if candidate_root == null:
			continue
		if candidate_root == body or candidate_root.is_ancestor_of(body):
			continue

		var priority: int = zone.get_zone_priority()
		var distance: float = body.global_position.distance_to(candidate_root.global_position)

		if priority > best_priority or (priority == best_priority and distance < best_distance):
			best_priority = priority
			best_distance = distance
			best_zone = zone

	if best_zone == null:
		body.call("set_zero_g")
		return

	best_zone.apply_gravity_to(body)
