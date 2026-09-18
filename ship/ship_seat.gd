extends Area3D
class_name ShipSeat
## Seat the player can enter to pilot the ship.
##
## RADICALLY SIMPLIFIED: no reparenting, no manual camera transform lerp,
## no deferred calls chasing scene tree locks. The ship has its OWN
## Camera3D sitting in the cockpit from the start (seat_camera export).
## Sitting down just:
##   1. hides + disables the player's physics body (it stays exactly where
##      it was, invisible and non-colliding, until you stand up again)
##   2. switches the active camera via Camera3D.current = true
##   3. flips control to the ship
## Standing up reverses all three. This is the standard, boring, reliable
## way to do vehicle seats - see Godot docs on Camera3D.current.

signal player_seated
signal player_unseated

@export var seat_camera: Camera3D
@export var interaction_prompt_label: Label3D
@export var ship_controller: Node
@export var exit_position: Node3D

var player_controller: CharacterBody3D = null
var player_camera: Camera3D = null
var player_collision_shape: CollisionShape3D = null

var is_player_in_range: bool = false
var _is_seated: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if interaction_prompt_label:
		interaction_prompt_label.visible = false
	_validate_exports()

func _validate_exports() -> void:
	if seat_camera == null:
		push_error("ShipSeat (%s): 'Seat Camera' export is not assigned" % name)
	if ship_controller == null:
		push_error("ShipSeat (%s): 'Ship Controller' export is not assigned" % name)
	if exit_position == null:
		push_error("ShipSeat (%s): 'Exit Position' export is not assigned" % name)

func _resolve_player_references() -> bool:
	if player_controller != null and is_instance_valid(player_controller):
		return true

	var found_player: Node = get_tree().get_first_node_in_group("player")
	if found_player == null:
		push_error("ShipSeat: no node in 'player' group found")
		return false

	player_controller = found_player as CharacterBody3D
	player_camera = found_player.get_node_or_null("BodyPivot/CameraPivot/PlayerCamera")
	player_collision_shape = found_player.get_node_or_null("CollisionShape3D")

	if player_controller == null or player_camera == null:
		push_error("ShipSeat: player found but expected child nodes missing (BodyPivot/CameraPivot/PlayerCamera)")
		return false

	return true

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		is_player_in_range = true
		if interaction_prompt_label and not _is_seated:
			interaction_prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		is_player_in_range = false
		if interaction_prompt_label:
			interaction_prompt_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not is_player_in_range and not _is_seated:
		return
	if event.is_action_pressed("interact"):
		if not _is_seated:
			_seat_player()
		else:
			_unseat_player()

func _seat_player() -> void:
	if seat_camera == null or ship_controller == null:
		push_error("ShipSeat: cannot seat, required exports missing")
		return
	if not _resolve_player_references():
		return

	_is_seated = true

	player_controller.call("set_controllable", false)
	player_controller.velocity = Vector3.ZERO
	player_controller.visible = false
	if player_collision_shape:
		player_collision_shape.disabled = true

	if interaction_prompt_label:
		interaction_prompt_label.visible = false

	seat_camera.current = true
	ship_controller.call("set_piloted", true)
	player_seated.emit()

func _unseat_player() -> void:
	_is_seated = false

	if exit_position:
		player_controller.global_transform = exit_position.global_transform
		if ship_controller and ship_controller.has_method("get_current_velocity"):
			var exit_velocity: Vector3 = ship_controller.call("get_current_velocity")
			print("UNSEAT: exit_position=", exit_position.global_position, " ship_velocity=", exit_velocity, " ship_gravity_source=", ship_controller.get_current_gravity_source())
			player_controller.velocity = exit_velocity
		else:
			player_controller.velocity = Vector3.ZERO
	player_controller.visible = true
	if player_collision_shape:
		player_collision_shape.disabled = false
	player_controller.call("set_controllable", true)

	player_camera.current = true
	ship_controller.call("set_piloted", false)

	if is_player_in_range and interaction_prompt_label:
		interaction_prompt_label.visible = true

	player_unseated.emit()
