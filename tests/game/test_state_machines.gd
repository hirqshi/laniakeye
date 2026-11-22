extends SceneTree
## Headless test. Run:
## godot --headless --path . --script res://tests/game/test_state_machines.gd

const PlayerModeScript = preload("res://game/core/player_mode.gd")
const TerrainSessionScript = preload("res://game/core/terrain_session.gd")

var _failures: int = 0


func _init() -> void:
	_test_player_mode()
	_test_terrain_session()
	if _failures == 0:
		print("GameStateMachines: PASS")
	else:
		printerr("GameStateMachines: FAIL count=%d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _test_player_mode() -> void:
	var machine = PlayerModeScript.new()
	var modes = PlayerModeScript.Mode
	var hits: Array = []
	machine.changed.connect(func(_from_mode: int, to_mode: int, _why: String) -> void: hits.append(to_mode))
	_check(machine.current == modes.NONE, "player starts in NONE")
	_check(not machine.request(modes.CONTACT_ACQUIRE), "NONE -> CONTACT_ACQUIRE is illegal")
	_check(machine.current == modes.NONE, "illegal request leaves state unchanged")
	_check(machine.last_error != "", "illegal request records last_error")
	_check(machine.request(modes.DEBUG_FLIGHT, "start"), "NONE -> DEBUG_FLIGHT")
	_check(not machine.request(modes.DEBUG_FLIGHT), "same-mode request rejected")
	_check(machine.request(modes.CONTACT_ACQUIRE, "landing"), "DEBUG_FLIGHT -> CONTACT_ACQUIRE")
	_check(machine.request(modes.DEBUG_FLIGHT, "abort"), "CONTACT_ACQUIRE abort returns to DEBUG_FLIGHT")
	_check(machine.request(modes.EVA, "weak gravity"), "DEBUG_FLIGHT -> EVA")
	_check(machine.previous == modes.DEBUG_FLIGHT, "previous mode is tracked")
	_check(machine.request(modes.WALK, "supported"), "EVA -> WALK")
	_check(not machine.request(modes.CONTACT_ACQUIRE), "WALK -> CONTACT_ACQUIRE is illegal")
	_check(machine.is_physical() and not machine.is_airborne_control(), "WALK is physical, not airborne control")
	_check(hits.size() == 5, "changed signal fired once per legal transition")


func _test_terrain_session() -> void:
	var session = TerrainSessionScript.new()
	var states = TerrainSessionScript.State
	_check(session.current == states.IDLE, "terrain starts IDLE")
	_check(not session.request(states.STAGED), "IDLE -> STAGED is illegal")
	_check(session.request(states.PREPARING, "approach"), "IDLE -> PREPARING")
	_check(session.is_transitioning() and not session.is_edit_allowed(), "PREPARING is transitioning, no edits")
	_check(session.request(states.STAGED), "PREPARING -> STAGED")
	_check(session.request(states.ACTIVE), "STAGED -> ACTIVE")
	_check(session.is_edit_allowed() and not session.is_transitioning(), "ACTIVE allows edits")
	_check(session.request(states.PREPARING), "ACTIVE can prepare next patch while current is retained")
	_check(session.request(states.ACTIVE, "cancel, previous terrain retained"), "PREPARING cancel returns to ACTIVE")
	_check(session.request(states.REANCHORING), "ACTIVE -> REANCHORING")
	_check(not session.is_edit_allowed(), "no edits while REANCHORING")
	_check(session.request(states.ROLLBACK, "build guard failed"), "REANCHORING -> ROLLBACK")
	_check(session.request(states.ACTIVE), "ROLLBACK -> ACTIVE restores terrain")
	session.bind_body(&"body_a", 7)
	_check(session.body_id == &"body_a" and session.revision == 7, "bind_body stores body and revision")
