extends CharacterBody3D

## Ship as CharacterBody3D - no physics solver fighting us, we fully own
## velocity every frame.
##
## AXIS FIX: Godot's convention is -Z = forward, +Z = back. Input.get_axis
## (negative, positive) returns +1 when the POSITIVE action is pressed, so
## "move_forward" giving +1 on local Z would mean backward - negated
## explicitly below, same for up/down.
##
## GRAVITY: implements the same duck-typed interface the player uses
## (set_planet_gravity / set_zero_g / get_current_gravity_source), so the
## planet gravity Area3D can notify the ship the same way it notifies the
## player. Applied as acceleration added to velocity every frame the ship
## isn't magnet-locked/parked, using the same inverse-falloff curve as the
## player controller.
##
## PARKED ANCHOR: while parked, BOTH position and orientation are tracked
## relative to gravity_source's own local space and re-derived from
## gravity_source's current transform every frame - a landed ship rides
## along with the planet's rotation/translation exactly.
##
## FIX (ship stays fixed in world space, "planet spins under it"): the
## anchor was only ever ESTABLISHED inside _run_magnet_landing_frame(),
## which only runs while is_piloted is true. If gravity_source hadn't been
## assigned yet at the exact moment the pilot exited the seat (e.g. the
## planet gravity zone's deferred reevaluation hadn't caught up yet),
## _parked_anchor_valid stayed false forever after - the unpiloted branch
## then just froze the ship at a fixed world transform with no way to ever
## recover, since it never re-attempted to establish the anchor once
## unpiloted. Fixed by lazily establishing the anchor in _process_unpiloted
## itself the moment gravity_source becomes valid, instead of requiring it
## to have already been valid during the last piloted frame.
##
## LANDING MAGNET: uses an exported RayCast3D (landing_raycast) pointed
## along the ship's local -Y. Orientation aligns to the surface normal via
## slerp; position eases onto the surface via lerp instead of snapping
## instantly.
##
## IMPORTANT: landing_offset_m must match the distance from this body's
## origin to its actual hull belly, or the ship will hover above or clip
## into the ground when landed.
##
## SCENE SETUP REQUIRED: add a RayCast3D child, point it straight down in
## local space (target_position = Vector3(0, -X, 0), X > landing_engage_
## distance_m), enable it, set its collision_mask to your terrain/deck
## layers, and assign it to landing_raycast below.

signal speed_changed(speed_ratio: float)

@export var thrust_acceleration: float = 20.0
@export var strafe_acceleration: float = 14.0
@export var max_speed: float = 60.0
@export var linear_damping: float = 0.4
@export var rotation_speed: float = 1.5
@export var mouse_sensitivity: float = 0.002

## landing magnet settings - TUNE landing_offset_m to your hull shape.
## landing_raycast's length/mask/exceptions are set on the RayCast3D node
## itself in the inspector, not here.
@export var landing_raycast: RayCast3D
@export var landing_offset_m: float = 1.0
@export var landing_engage_distance_m: float = 6.0
@export var landing_align_speed: float = 3.0
@export var landing_position_smoothing_speed: float = 12.0
@export var landing_vertical_release_threshold: float = 0.15
@export var landing_max_reorientation_deg: float = 75.0

## gravity - mirrors player_controller's falloff curve
@export var gravity_fade_curve_power: float = 1.5
@export var gravity_multiplier: float = 1.0

@export var ship_seat: Node3D

var is_piloted: bool = false
var _is_parked: bool = false

var gravity_source: Node3D = null
var surface_gravity_strength: float = 9.8

# parked anchor - keeps a landed ship glued to its spot on a
# rotating/moving gravity_source, in BOTH position and orientation,
# instead of freezing at a fixed world transform.
var _parked_local_offset: Vector3 = Vector3.ZERO
var _parked_local_basis: Basis = Basis.IDENTITY
var _parked_anchor_valid: bool = false

func _ready() -> void:
	if landing_raycast == null:
		push_error("ShipController (%s): 'Landing Raycast' export is not assigned" % name)
	elif not landing_raycast.enabled:
		push_warning("ShipController (%s): landing_raycast is disabled, landing magnet will never engage" % name)

func set_piloted(value: bool) -> void:
	is_piloted = value

## Duck-typed gravity interface, matching what the player exposes - the
## planet's gravity Area3D calls this the same way it calls the player.
func set_planet_gravity(source: Node3D, strength: float) -> void:
	gravity_source = source
	surface_gravity_strength = strength

func set_zero_g() -> void:
	gravity_source = null
	_parked_anchor_valid = false

func get_current_gravity_source() -> Node3D:
	return gravity_source

func _physics_process(delta: float) -> void:
	if not is_piloted:
		_process_unpiloted(delta)
		return

	var strafe_input: float = Input.get_axis("move_left", "move_right")
	var vertical_input: float = Input.get_axis("move_down", "move_up")
	var forward_input: float = Input.get_axis("move_back", "move_forward")

	# forward_input is +1 when pressing "move_forward", but local -Z is
	# forward in Godot, so we feed it as negative Z here.
	var input_dir: Vector3 = Vector3(strafe_input, vertical_input, -forward_input)

	var wants_liftoff: bool = vertical_input > landing_vertical_release_threshold
	var probe: Dictionary = _probe_landing_surface()
	var can_magnet: bool = probe.found and probe.distance <= landing_engage_distance_m and not wants_liftoff

	if can_magnet:
		_run_magnet_landing_frame(input_dir, probe, delta)
		return

	_is_parked = false
	_parked_anchor_valid = false

	if input_dir.length() > 0.01:
		var accel_dir: Vector3 = (global_transform.basis * input_dir).normalized()
		var accel: float = thrust_acceleration if absf(forward_input) > 0.01 else strafe_acceleration
		velocity += accel_dir * accel * delta
	else:
		velocity = velocity.lerp(Vector3.ZERO, linear_damping * delta)

	_apply_gravity(delta)

	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed

	move_and_slide()

	var speed_ratio: float = clamp(velocity.length() / max_speed, 0.0, 1.0)
	speed_changed.emit(speed_ratio)

## Handles the unpiloted case: either the ship is parked (glued to its
## spot on gravity_source in both position AND orientation) or it's
## coasting/falling freely. If parked but the anchor was never
## established (gravity_source wasn't assigned yet at the moment the
## pilot exited), it's lazily established here the moment gravity_source
## becomes valid, instead of staying permanently frozen in world space.
func _process_unpiloted(delta: float) -> void:
	if _is_parked and is_instance_valid(gravity_source):
		if not _parked_anchor_valid:
			_parked_local_offset = gravity_source.to_local(global_position)
			_parked_local_basis = gravity_source.global_transform.basis.inverse() * global_transform.basis
			_parked_anchor_valid = true

		global_position = gravity_source.to_global(_parked_local_offset)
		global_transform.basis = (gravity_source.global_transform.basis * _parked_local_basis).orthonormalized()
		velocity = Vector3.ZERO
		move_and_slide()
		speed_changed.emit(0.0)
		return

	if _is_parked:
		# parked with no gravity_source at all (e.g. docked in deep space,
		# or gravity_source genuinely never assigned) - nothing to follow,
		# just stay bit-exact in place.
		velocity = Vector3.ZERO
		move_and_slide()
		speed_changed.emit(0.0)
		return

	velocity = velocity.lerp(Vector3.ZERO, linear_damping * delta)
	_apply_gravity(delta)
	move_and_slide()
	speed_changed.emit(0.0)

## Adds gravitational acceleration toward gravity_source's center to
## velocity, using the same inverse-falloff curve as the player
## controller. No-op if there's no active gravity source.
func _apply_gravity(delta: float) -> void:
	if not is_instance_valid(gravity_source):
		return

	var to_center: Vector3 = gravity_source.global_position - global_position
	var distance_to_center: float = to_center.length()
	if distance_to_center < 0.01:
		return

	var gravity_dir: Vector3 = to_center / distance_to_center
	var gravity_strength: float = _get_falloff_gravity_strength(distance_to_center)
	velocity += gravity_dir * gravity_strength * delta

func _get_falloff_gravity_strength(distance_to_center: float) -> float:
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

## Runs one frame of magnet-locked landing: orientation smoothly aligns to
## the surface normal, horizontal thrust input still allows taxiing, and
## position eases onto the surface via lerp. Also refreshes the parked
## anchor (position AND orientation expressed in gravity_source's local
## space) so an unpiloted parked ship can keep following a rotating body.
func _run_magnet_landing_frame(input_dir: Vector3, probe: Dictionary, delta: float) -> void:
	var safe_current_basis: Basis = global_transform.basis.orthonormalized()
	var target_basis: Basis = _basis_from_up(probe.normal, safe_current_basis)
	global_transform.basis = safe_current_basis.slerp(target_basis, landing_align_speed * delta).orthonormalized()

	var tangential_input: Vector3 = Vector3(input_dir.x, 0.0, input_dir.z)
	var horizontal_velocity: Vector3 = Vector3.ZERO

	if tangential_input.length() > 0.01:
		var accel_dir: Vector3 = (global_transform.basis * tangential_input).normalized()
		accel_dir -= accel_dir.project(probe.normal)
		if accel_dir.length() > 0.001:
			horizontal_velocity = accel_dir.normalized() * strafe_acceleration

	velocity = horizontal_velocity
	move_and_slide()

	var post_probe: Dictionary = _probe_landing_surface()
	if post_probe.found:
		var target_position: Vector3 = post_probe.hit_point + post_probe.normal * landing_offset_m
		global_position = global_position.lerp(target_position, clamp(landing_position_smoothing_speed * delta, 0.0, 1.0))

	if is_instance_valid(gravity_source):
		_parked_local_offset = gravity_source.to_local(global_position)
		_parked_local_basis = gravity_source.global_transform.basis.inverse() * global_transform.basis
		_parked_anchor_valid = true
	else:
		_parked_anchor_valid = false

	_is_parked = true

	var speed_ratio: float = clamp(horizontal_velocity.length() / max_speed, 0.0, 1.0)
	speed_changed.emit(speed_ratio)

## Reads the exported RayCast3D to look for a nearby surface to land on.
## Rejects degenerate normals and hits that would require too extreme a
## reorientation from the ship's current up (landing_max_reorientation_deg).
func _probe_landing_surface() -> Dictionary:
	var not_found: Dictionary = {"found": false, "hit_point": Vector3.ZERO, "normal": Vector3.ZERO, "distance": INF}

	if landing_raycast == null or not landing_raycast.enabled:
		return not_found

	landing_raycast.force_raycast_update()
	if not landing_raycast.is_colliding():
		return not_found

	var normal: Vector3 = landing_raycast.get_collision_normal()
	if normal.length_squared() < 0.0001:
		return not_found
	normal = normal.normalized()

	var ship_up: Vector3 = global_transform.basis.y.normalized()
	var max_reorientation_cos: float = cos(deg_to_rad(landing_max_reorientation_deg))
	if normal.dot(ship_up) < max_reorientation_cos:
		return not_found

	var hit_point: Vector3 = landing_raycast.get_collision_point()
	var distance: float = (global_position - hit_point).dot(ship_up)
	return {"found": true, "hit_point": hit_point, "normal": normal, "distance": distance}

## Builds an orthonormal basis with the given up direction, preserving as
## much of the current forward heading as possible. new_up is defensively
## normalized; current_basis is assumed already orthonormal (callers must
## pass a sanitized basis - see safe_current_basis above).
func _basis_from_up(raw_new_up: Vector3, current_basis: Basis) -> Basis:
	var new_up: Vector3 = raw_new_up.normalized()
	if new_up.length_squared() < 0.0001:
		new_up = current_basis.y.normalized()

	var forward: Vector3 = -current_basis.z
	forward = (forward - new_up * forward.dot(new_up)).normalized()

	if forward.length_squared() < 0.001:
		forward = current_basis.x.cross(new_up).normalized()

	if forward.length_squared() < 0.001:
		var safe_axis: Vector3 = Vector3.FORWARD if absf(new_up.y) < 0.99 else Vector3.RIGHT
		forward = (safe_axis - new_up * safe_axis.dot(new_up)).normalized()

	var right: Vector3 = forward.cross(new_up).normalized()
	return Basis(right, new_up, -forward)

func _unhandled_input(event: InputEvent) -> void:
	if not is_piloted:
		return
	if event is InputEventMouseMotion:
		rotate_object_local(Vector3.UP, -event.relative.x * mouse_sensitivity)
		rotate_object_local(Vector3.RIGHT, -event.relative.y * mouse_sensitivity)
		# periodically re-orthonormalize to prevent float32 drift from many
		# accumulated incremental rotations over a long play session from
		# ever exceeding Godot's strict is_rotation() tolerance later.
		global_transform.basis = global_transform.basis.orthonormalized()

func get_seat_exit_transform() -> Transform3D:
	if ship_seat == null:
		push_error("ShipController (%s): 'Ship Seat' export is not assigned" % name)
		return global_transform

	var exit_position: Node3D = ship_seat.get("exit_position")
	if exit_position == null:
		push_error("ShipController (%s): ship_seat has no valid 'exit_position' assigned" % name)
		return global_transform

	return exit_position.global_transform
