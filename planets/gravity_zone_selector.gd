class_name GravityZoneSelector
extends RefCounted

## Shared logic for picking which gravity zone a body should currently
## belong to, used by BOTH the ship interior zone and the planet exterior
## zone. Any Area3D in the "planet_gravity_zone" group that implements
## get_gravity_root() and apply_gravity_to(body) can participate.
##
## Both entered and exited handlers on participating zones should call
## this via call_deferred, consistently, so relative event ordering is
## preserved and a stale reevaluation from one zone can't stomp a fresher
## one from another.

static func reevaluate(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	if not body.has_method("set_zero_g"):
		return

	var closest_zone: Area3D = null
	var closest_root: Node3D = null
	var closest_distance: float = INF

	for area in body.get_tree().get_nodes_in_group("planet_gravity_zone"):
		if not area is Area3D:
			continue
		if not area.has_method("get_gravity_root") or not area.has_method("apply_gravity_to"):
			continue
		if not area.overlaps_body(body):
			continue

		var candidate_root: Node3D = area.call("get_gravity_root")
		if candidate_root == null:
			continue
		if candidate_root == body or candidate_root.is_ancestor_of(body):
			continue

		var distance: float = body.global_position.distance_to(candidate_root.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_zone = area
			closest_root = candidate_root

	if closest_zone == null:
		body.call("set_zero_g")
		return

	closest_zone.call("apply_gravity_to", body)
