extends Node

## Owns spawn/respawn logic for the player and ship. Does NOT own system
## generation (that's StarSystem's job) - this script runs AFTER StarSystem
## has already built system_data, then places the ship at a safe point and
## the player at the ship's seat exit position.
##
## "Return to ship" hotkey ("return" action, already in the Input Map)
## teleports the player back to the exact same exit_position at any time -
## this is also what the initial spawn uses, so there's only one source of
## truth for "where the player belongs when not exploring on foot".
##
## FIX: exit_position is NOT exported directly on World (ShipSeat lives
## nested inside the ship's own scene, and World shouldn't need to reach
## into the ship's internal node structure to get it - that's exactly the
## kind of "reaching into another system's internals" the project's
## architecture rules warn against). Instead, ship_controller.gd exposes
## get_seat_exit_transform() and World only ever talks to `ship`.

@export var star_system: Node3D
@export var ship: CharacterBody3D
@export var player: CharacterBody3D

@export var star_radius_m: float = 300.0
@export var ship_spawn_margin_m: float = 100.0
@export var ship_spawn_body_clearance_m: float = 30.0
@export var ship_spawn_max_attempts: int = 64

@export var hud: HudController

@export var seat_enter_stream: AudioStream
@export var seat_exit_stream: AudioStream
@export var return_to_ship_stream: AudioStream
@export_range(-24.0, 6.0, 0.1) var seat_audio_volume_db: float = -4.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	if not _validate_exports():
		return

	_rng.randomize()

	var spawn_position: Vector3 = _find_safe_ship_spawn_position()
	
	ship.global_position = spawn_position
	ship.velocity = Vector3.ZERO
	
	_teleport_player_to_ship_seat()

	call_deferred("_register_floating_origin")
	_setup_hud()

func _register_floating_origin() -> void:
	FloatingOriginManager.register(player, ship, star_system)

func _validate_exports() -> bool:
	var all_valid: bool = true

	if star_system == null:
		push_error("World: 'Star System' export is not assigned")
		all_valid = false
	if ship == null:
		push_error("World: 'Ship' export is not assigned")
		all_valid = false
	if player == null:
		push_error("World: 'Player' export is not assigned")
		all_valid = false
	elif not ship.has_method("get_seat_exit_transform"):
		push_error("World: 'Ship' does not implement get_seat_exit_transform()")
		all_valid = false

	return all_valid

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("return"):
		_teleport_player_to_ship_seat()

		if is_instance_valid(player):
			AudioManager.play_sfx_3d(
				return_to_ship_stream,
				player.global_position,
				seat_audio_volume_db
			)

## Teleports the player to the ship's seat exit transform - the single
## authoritative "player belongs here when not on foot" point. Used both
## for the initial spawn and for the "return to ship" hotkey.
func _teleport_player_to_ship_seat() -> void:
	if not is_instance_valid(player) or not is_instance_valid(ship):
		return

	var exit_transform: Variant = ship.call("get_seat_exit_transform")
	if exit_transform == null:
		push_error("World: ship.get_seat_exit_transform() returned null")
		return

	if player.has_method("set_controllable"):
		player.call("set_controllable", false)

	player.global_transform = exit_transform
	player.velocity = Vector3.ZERO

	if player.has_method("set_controllable"):
		player.call("set_controllable", true)

## Finds a random point that clears the star's surface, EVERY planet's
## current position, and EVERY moon's current position (moons move, so
## this is checked against their live world position, not just orbit
## math), while staying within the system's own outer bound so the ship
## doesn't spawn flung out into empty space.
func _find_safe_ship_spawn_position() -> Vector3:
	var system_data: SystemData = star_system.get("system_data")
	var star_center: Vector3 = star_system.global_position
	var star_radius_m: float = star_system.call("get_radius")
	var outer_bound_m: float = _compute_outer_bound_m(system_data, star_radius_m)

	for attempt in range(ship_spawn_max_attempts):
		var candidate: Vector3 = _random_point_in_shell(
			star_center,
			star_radius_m + ship_spawn_margin_m,
			outer_bound_m
		)

		if _is_position_clear(candidate, system_data, star_center, star_radius_m):
			return candidate

	push_warning("World: could not find a clear random ship spawn after %d attempts, using polar fallback" % ship_spawn_max_attempts)
	return star_center + Vector3.UP * (outer_bound_m + ship_spawn_margin_m)

func _compute_outer_bound_m(system_data: SystemData, star_radius_m: float) -> float:
	var outer_bound_m: float = star_radius_m + ship_spawn_margin_m

	if system_data == null:
		return outer_bound_m

	for planet_data in system_data.planets:
		var planet_outer_m: float = planet_data.orbit_distance_m + planet_data.radius_m
		outer_bound_m = max(outer_bound_m, planet_outer_m)

		for moon_data in planet_data.moons:
			var moon_outer_m: float = planet_data.orbit_distance_m + moon_data.orbit_distance_m + moon_data.radius_m
			outer_bound_m = max(outer_bound_m, moon_outer_m)

	return outer_bound_m + ship_spawn_margin_m

func _is_position_clear(candidate: Vector3, system_data: SystemData, star_center: Vector3, star_radius_m: float) -> bool:
	if candidate.distance_to(star_center) < star_radius_m + ship_spawn_body_clearance_m:
		return false

	if system_data == null:
		return true

	for planet_data in system_data.planets:
		var planet_position: Vector3 = planet_data.get_orbit_position(star_center)
		var required_clearance: float = planet_data.radius_m + ship_spawn_body_clearance_m

		if candidate.distance_to(planet_position) < required_clearance:
			return false

		for moon_data in planet_data.moons:
			var moon_position: Vector3 = moon_data.get_orbit_position(planet_position)
			var moon_clearance: float = moon_data.radius_m + ship_spawn_body_clearance_m

			if candidate.distance_to(moon_position) < moon_clearance:
				return false

	return true

func _random_point_in_shell(center: Vector3, min_distance_m: float, max_distance_m: float) -> Vector3:
	var direction: Vector3 = Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	)

	if direction.length_squared() < 0.0001:
		direction = Vector3.UP
	else:
		direction = direction.normalized()

	var distance_m: float = _rng.randf_range(min_distance_m, max_distance_m)
	return center + direction * distance_m

func _setup_hud() -> void:
	if hud == null:
		push_warning("World: 'Hud' export is not assigned")
		return

	var player_camera: Camera3D = player.get("player_camera")
	if player_camera == null:
		push_error("World: player has no 'player_camera' property")
		return

	var leviathan_spawner: LeviathanSpawner = null

	if star_system.has_method("get_leviathan_spawner"):
		leviathan_spawner = star_system.call("get_leviathan_spawner")

	hud.set_star_system(star_system)
	hud.set_leviathan_spawner(leviathan_spawner)
	hud.set_ship_reference(player_camera, ship)
	hud.set_player_and_ship(player, ship)
	hud.set_piloting_ship(false)

	if ship.has_signal("player_seated"):
		ship.connect("player_seated", _on_player_seated)
	if ship.has_signal("player_unseated"):
		ship.connect("player_unseated", _on_player_unseated)

func _on_player_seated() -> void:
	if hud == null:
		return
	hud.set_ship_reference(ship.call("get_seat_camera"), ship)
	hud.set_piloting_ship(true)

	if is_instance_valid(ship):
		AudioManager.play_sfx_3d(
			seat_enter_stream,
			ship.global_position,
			seat_audio_volume_db
		)

func _on_player_unseated() -> void:
	if hud == null:
		return
	var player_camera: Camera3D = player.get_player_camera()
	if player_camera:
		hud.set_ship_reference(player_camera, ship)
	hud.set_piloting_ship(false)

	if is_instance_valid(ship):
		AudioManager.play_sfx_3d(
			seat_exit_stream,
			ship.global_position,
			seat_audio_volume_db
		)
