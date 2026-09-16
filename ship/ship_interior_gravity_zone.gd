extends Area3D

## Gravity zone for walking around INSIDE the ship's hull (not the seat -
## this is for a player who is NOT piloting, just walking around the
## interior). Unlike planet gravity (which pulls toward a center point),
## ship interior gravity pulls toward the ship's local -Y axis, i.e.
## "down" relative to the ship's own orientation - so it still works
## correctly while the ship is flying/rotating in space.
##
## Uses the same set_planet_gravity/set_zero_g duck-typed interface as
## planets, but passes a synthetic "floor point" that sits directly below
## the player along the ship's local down direction, updated every frame
## by the player itself (see player_controller changes needed: gravity
## sources with a get_local_down() method are treated as "flat floor"
## gravity instead of "sphere center" gravity).

@export var ship_root: Node3D
@export var interior_gravity_strength: float = 9.8

func _ready() -> void:
	add_to_group("planet_gravity_zone")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("set_planet_gravity") or not body.has_method("set_zero_g"):
		return
	if body == ship_root or ship_root.is_ancestor_of(body):
		return
	body.call("set_flat_gravity", ship_root, interior_gravity_strength)

func _on_body_exited(body: Node3D) -> void:
	if not body.has_method("set_zero_g"):
		return
	if body.has_method("get_current_gravity_source") and body.call("get_current_gravity_source") == ship_root:
		body.call("set_zero_g")

func get_radius() -> float:
	return 0.0

func get_gravity_zone_radius() -> float:
	return 999999.0
