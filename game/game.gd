class_name LkGame
extends Node3D
## Composition root. Owns the shared state machines, the event bus, the world clock and the world.
## Systems live in child components and talk through LkGameEvents, not direct references.

var events: LkGameEvents = LkGameEvents.new()
var player_mode: LkPlayerMode = LkPlayerMode.new()
var terrain_session: LkTerrainSession = LkTerrainSession.new()
var clock: LkClockService = LkClockService.new()
var world: LkWorldService


func _init() -> void:
	world = LkWorldService.new(LkUniverseDefinition.new(), clock)
	# The object graph is wired at construction, so it already works before the node
	# enters the scene tree (tests, tools) and does not depend on _ready() timing.
	player_mode.changed.connect(_on_player_mode_changed)
	terrain_session.changed.connect(_on_terrain_state_changed)
	clock.failed.connect(_on_clock_failed)
	world.activated.connect(_on_body_activated)
	world.failed.connect(_on_world_failed)


func _ready() -> void:
	print("Game: READY skeleton player_mode=%s terrain=%s" % [LkPlayerMode.mode_name(player_mode.current), LkTerrainSession.state_name(terrain_session.current)])


## Opens the clock of the world's own universe and activates the body at `address`.
func start(address: Dictionary) -> bool:
	if not open_universe(world.definition.get_universe_id()):
		return false
	if not world.activate(address):
		clock.close()
		return false
	return true


## Opens (loads or starts) the persistent clock of one universe. Call before gameplay starts.
func open_universe(universe_id: String) -> bool:
	if not clock.open(universe_id):
		return false
	print("Game: CLOCK open universe=%s found=%s epoch=%.6f" % [universe_id, clock.loaded_existing, clock.now_s()])
	return true


# One owner advances time exactly once per physics tick, then the world syncs to it.
func _physics_process(delta: float) -> void:
	if not clock.is_open():
		return
	if clock.advance(delta):
		world.tick(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and clock.is_open():
		if not clock.close():
			push_error("Game: clock save on close failed: " + clock.last_error)


func _on_clock_failed(reason: String) -> void:
	push_error("Game: CLOCK " + reason)
	set_physics_process(false)


func _on_world_failed(reason: String) -> void:
	push_error("Game: WORLD " + reason)


func _on_body_activated(body_id: StringName) -> void:
	events.body_activated.emit(body_id)
	print("Game: BODY active=%s epoch=%.6f" % [String(body_id).left(8), clock.now_s()])


func _on_player_mode_changed(from_mode: int, to_mode: int, why: String) -> void:
	events.player_mode_changed.emit(from_mode, to_mode, why)
	print("Game: PLAYER_MODE %s -> %s reason=%s" % [LkPlayerMode.mode_name(from_mode), LkPlayerMode.mode_name(to_mode), why])


func _on_terrain_state_changed(from_state: int, to_state: int, why: String) -> void:
	events.terrain_state_changed.emit(from_state, to_state, why)
	print("Game: TERRAIN %s -> %s reason=%s" % [LkTerrainSession.state_name(from_state), LkTerrainSession.state_name(to_state), why])
