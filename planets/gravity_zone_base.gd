class_name GravityZone
extends Area3D
## Base class for anything that can pull a body into a gravity mode.
## Concrete zones (PlanetExteriorZone in gravity_zone.gd, ship interior
## zone in planet_gravity_zone.gd) extend this and override the virtuals
## below.
##
## Replaces the old has_method()/call()-by-string duck-typing pattern in
## GravityZoneSelector: with a real base class, `area as GravityZone`
## either succeeds or the area isn't a gravity zone - no silent typos in
## method name strings, and full autocomplete/type-checking.
##
## Subclasses are still expected to add_to_group("planet_gravity_zone")
## and wire up body_entered/body_exited themselves, since the two current
## zone types differ slightly in what "supports gravity" means for them
## (kept as-is rather than pulled up, to avoid restructuring signal wiring
## in the same pass as the type change).

## Higher priority wins when multiple zones overlap (e.g. standing inside
## a ship that's parked within a planet's gravity zone - the ship
## interior zone should win over the planet's).
func get_zone_priority() -> int:
	return 0


func get_gravity_root() -> Node3D:
	return null


## Applies whichever gravity mode this zone represents to body. body is
## expected to implement set_planet_gravity/set_flat_gravity/set_zero_g -
## that contract stays duck-typed for now (only Player and Ship implement
## it), since formalizing a full GravityReceiver interface class isn't
## worth it yet for two callers.
func apply_gravity_to(_body: Node3D) -> void:
	pass
