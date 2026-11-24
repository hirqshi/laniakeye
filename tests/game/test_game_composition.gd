extends SceneTree
## Headless test of the composition root. Run:
## godot --headless --path . --script res://tests/game/test_game_composition.gd

const GameScene = preload("res://game/game.tscn")
const WorldServiceScript = preload("res://game/world/world_service.gd")
const ClockStore = preload("res://game/world/runtime/lk_world_clock_store.gd")
const Identity = preload("res://game/world/generation/lk_world_identity.gd")

var _failures: int = 0


func _initialize() -> void:
	_run()
	if _failures == 0:
		print("GameComposition: PASS")
	else:
		printerr("GameComposition: FAIL count=%d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _remove_fixture(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists(path + ".tmp"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path.get_base_dir()))


func _run() -> void:
	var universe: String = Identity.child_id(Identity.universe_id("game-composition-test"), "test_fixture", "game_composition_v1")
	var path: String = ClockStore.clock_path(universe)
	_remove_fixture(path)

	var game = GameScene.instantiate()
	root.add_child(game)
	_check(game.clock != null and game.world != null, "the game owns the clock and the world")

	var announced: Array = []
	game.events.body_activated.connect(func(id: StringName) -> void: announced.append(id))
	_check(game.open_universe(universe), "open the fixture universe")
	var address: Dictionary = WorldServiceScript.make_address(0, 0, 0, 0, 0, 0)
	_check(game.world.activate(address), "activate a body")
	_check(announced.size() == 1 and announced[0] == game.world.active_body_id(), "activation is announced on the event bus")

	var start: float = game.clock.now_s()
	for tick: int in range(60):
		game._physics_process(1.0 / 60.0)
	_check(absf(game.clock.now_s() - start - 1.0) < 1.0e-9, "the game advances the clock once per physics tick")
	_check(game.world.active_frame.world_time_s == game.clock.now_s(), "the body frame follows the clock")
	var angle: float = game.world.active_frame.angle_rad
	_check(game.world.tick(1.0 / 60.0) == 0.0 and game.world.active_frame.angle_rad == angle, "an extra world tick without clock progress changes nothing")

	_check(game.clock.close(), "close the clock")
	root.remove_child(game)
	game.free()
	_remove_fixture(path)
