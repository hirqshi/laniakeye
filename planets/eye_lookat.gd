extends Node3D

## Rotates this node to always face the PLAYER'S BODY POSITION (not the
## camera - the two can differ, e.g. head bob, third-person offset, or a
## detached spectator camera). A plain billboard (SpriteBase3D-style,
## screen-facing) doesn't work here because this is presumably a 3D eye
## mesh that needs to physically rotate in world space toward a point,
## not just face the screen plane.
##
## Uses look_at() rather than a raw Basis.looking_at() call so scale is
## preserved automatically (see Node3D.look_at docs). Godot's look_at
## degenerates when the target direction is exactly parallel to the up
## vector (looking straight along world +Y) - handled by swapping to a
## non-parallel fallback up axis in that case, per Godot's documented
## behavior for this edge case.

@export var player: Node3D
@export var use_own_up_as_reference: bool = true

func _ready() -> void:
	if player == null:
		var found_player: Node = get_tree().get_first_node_in_group("player")
		if found_player is Node3D:
			player = found_player
		else:
			push_error("EyeLookAtPlayer (%s): no 'player' assigned and none found in 'player' group" % name)

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return

	var to_player: Vector3 = player.global_position - global_position
	if to_player.length_squared() < 0.0001:
		return

	var forward: Vector3 = to_player.normalized()
	var up_reference: Vector3 = (global_transform.basis.y if use_own_up_as_reference else Vector3.UP)

	# look_at() requires the direction to target to not be parallel to the
	## up vector - swap to a safe fallback axis in that rare case instead
	## of letting Godot pick an undefined/flipped orientation.
	if absf(forward.dot(up_reference.normalized())) > 0.999:
		up_reference = Vector3.FORWARD if absf(forward.dot(Vector3.FORWARD)) < 0.999 else Vector3.RIGHT

	look_at(player.global_position, up_reference)
