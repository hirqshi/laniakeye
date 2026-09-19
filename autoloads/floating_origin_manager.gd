extends Node
## Autoload. Keeps the player near Vector3.ZERO by periodically shifting
## the whole star system (and any other registered absolute-position
## bodies) by an equal and opposite amount, instead of letting the player
## drift arbitrarily far from origin in float32 world space.
##
## WHY THIS WORKS WITH THE EXISTING CODEBASE WITH ALMOST NO OTHER CHANGES:
## StarSystem/PlanetData never store an absolute world position as their
## source of truth - PlanetData.get_orbit_position(center) recomputes the
## planet's global_position from the PARENT's global_position every
## physics frame (see star_system.gd _physics_process and planet.gd
## _physics_process). Same for moons relative to their planet. So shifting
## ONLY star_system.global_position is enough - every planet and moon
## re-derives its own corrected position on the very next physics frame
## for free, with zero changes needed in system_generator.gd/planet.gd.
##
## The two bodies that do NOT auto-correct are Player and Ship, because
## their global_position is driven by move_and_slide()/direct assignment,
## not by a parent-relative formula - those two are shifted explicitly
## here.
##
## gravity_source-relative state (player_controller.gd's _local_offset,
## ship_controller.gd's _parked_local_offset) needs no changes at all:
## they're stored as gravity_source.to_local(global_position), i.e.
## already relative to the planet/ship, not to absolute world space.
##
## ORDERING: this autoload's _physics_process must run BEFORE
## StarSystem's (-100) and well before Player/Ship's (default 0), so the
## shift is applied first and everything downstream reads the corrected
## values in the same frame. Autoloads process before scene tree nodes
## by default, but we still pin an explicit low priority defensively.

signal origin_shifted(shift: Vector3)

## Player crossing this distance from Vector3.ZERO triggers a shift.
## Set well above the largest expected system radius (outer_bound_m in
## world.gd) so shifts are rare - frequent shifting adds visible hitches
## if anything reacts to origin_shifted with heavy work.
@export var shift_threshold_m: float = 500.0

var _player: CharacterBody3D
var _ship: CharacterBody3D
var _star_system: Node3D

var _enabled: bool = false


func _ready() -> void:
	process_physics_priority = -200


## Called once by World._ready() after it has resolved star_system/
## player/ship references - this manager has no scene-tree access of its
## own by design (autoloads shouldn't reach into the current level).
func register(player: CharacterBody3D, ship: CharacterBody3D, star_system: Node3D) -> void:
	_player = player
	_ship = ship
	_star_system = star_system
	_enabled = is_instance_valid(_player) and is_instance_valid(_star_system)

	if not _enabled:
		push_warning("FloatingOriginManager: register() called with invalid player/star_system, shifting disabled")


func unregister() -> void:
	_player = null
	_ship = null
	_star_system = null
	_enabled = false


func _physics_process(_delta: float) -> void:
	if not _enabled:
		return
	if not is_instance_valid(_player):
		return

	var distance_from_origin: float = _player.global_position.length()
	if distance_from_origin < shift_threshold_m:
		return

	var shift: Vector3 = -_player.global_position
	_apply_shift(shift)


func _apply_shift(shift: Vector3) -> void:
	# Only the star system needs a direct shift - every planet and moon
	# re-derives its position from the star system's global_position on
	# its own next _physics_process (see class comment above).
	_star_system.global_position += shift

	# Player and ship are NOT parent-relative, so they need explicit
	# correction. Setting global_position directly (not through velocity)
	# is safe here: this runs before either body's own _physics_process
	# this frame (priority -200 vs their default/near-default priority),
	# so move_and_slide() afterwards operates on the already-corrected
	# position with its normal velocity - no collision/teleport artifact.
	_player.global_position += shift

	if is_instance_valid(_ship):
		_ship.global_position += shift

	origin_shifted.emit(shift)
