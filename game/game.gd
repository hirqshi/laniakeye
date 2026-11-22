class_name LkGame
extends Node3D
## Composition root. Owns the shared state machines and the event bus, nothing else.
## Systems live in child components and talk through LkGameEvents, not direct references.

var events: LkGameEvents = LkGameEvents.new()
var player_mode: LkPlayerMode = LkPlayerMode.new()
var terrain_session: LkTerrainSession = LkTerrainSession.new()


func _ready() -> void:
	player_mode.changed.connect(_on_player_mode_changed)
	terrain_session.changed.connect(_on_terrain_state_changed)
	print("Game: READY skeleton player_mode=%s terrain=%s" % [LkPlayerMode.mode_name(player_mode.current), LkTerrainSession.state_name(terrain_session.current)])


func _on_player_mode_changed(from_mode: int, to_mode: int, why: String) -> void:
	events.player_mode_changed.emit(from_mode, to_mode, why)
	print("Game: PLAYER_MODE %s -> %s reason=%s" % [LkPlayerMode.mode_name(from_mode), LkPlayerMode.mode_name(to_mode), why])


func _on_terrain_state_changed(from_state: int, to_state: int, why: String) -> void:
	events.terrain_state_changed.emit(from_state, to_state, why)
	print("Game: TERRAIN %s -> %s reason=%s" % [LkTerrainSession.state_name(from_state), LkTerrainSession.state_name(to_state), why])
