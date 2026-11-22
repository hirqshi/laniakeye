extends "res://scenes/world/test_catalog_stellar_light.gd"

const SharedClock = preload("res://game/world/runtime/lk_world_clock.gd")
const SharedClockStore = preload("res://game/world/runtime/lk_world_clock_store.gd")
const SharedBodyFrame = preload("res://game/world/runtime/lk_clocked_body_frame.gd")

var _universe_clock
var _clock_universe_id: String = ""
var _clock_autosave_s: float = 0.0
var _clock_ready: bool = false


func _ready() -> void:
	var definition = Definition.new()
	_clock_universe_id = definition.get_universe_id()
	var loaded: Dictionary = SharedClockStore.load_clock(_clock_universe_id)
	if not loaded["ok"]:
		_abort_start("world clock: " + str(loaded["error"]))
		return
	_universe_clock = loaded["clock"]
	_clock_ready = true
	print("WorldClock: LOAD found=%s epoch=%.6f path=%s" % [
		loaded["found"], _universe_clock.now_s(), SharedClockStore.clock_path(_clock_universe_id),
	])
	super._ready()


func _begin_spawn() -> void:
	# Parent construction is synchronous. Replace the provisional epoch-zero
	# frame BEFORE parent places/releases the player or any frame is rendered.
	_catalog_frame = SharedBodyFrame.new(StringName(_context["body"]["id"]), _context["spin"], _universe_clock)
	_rotation = _catalog_frame
	# Old origin was built at epoch zero. Replace the local coordinate frame,
	# rather than moving the world by a huge Vector3 or calling a large rebase.
	_frame.unregister_root(_player)
	_frame = LkCoordinateFrame.new()
	_frame.threshold_m = 64.0
	_frame.initialize_origin(_catalog_frame.body_to_inertial(_q0))
	_frame.shifted.connect(func(_shift: Vector3) -> void:
		_shifts += 1
		_update_terrain_transform()
	)
	_player.setup(_frame, _gravity)
	_frame.register_root(_player)
	_update_terrain_transform()
	super._begin_spawn()
	print("WorldClock: SPAWN body=%s epoch=%.6f" % [_context["body"]["id"], _universe_clock.now_s()])


func _load_target(index: int) -> void:
	if not _clock_ready or _switching or index < 0 or index >= _targets.size():
		return
	# Refuse to destroy the old world if saving its state fails.
	if _active_index >= 0 and not _save_journal():
		push_error("WorldClock: switch aborted; cannot save current world")
		return
	var before: float = _universe_clock.now_s()
	super._load_target(index)
	if _initialised and not _failed:
		print("WorldClock: SWITCH body=%s before=%.6f after=%.6f" % [
			_context["body"]["id"], before, _universe_clock.now_s(),
		])


func _save_journal() -> bool:
	if not super._save_journal():
		return false
	if not _clock_ready:
		return false
	return SharedClockStore.save_clock(_clock_universe_id, _universe_clock)


func _physics_process(delta: float) -> void:
	if not _clock_ready or not _initialised or _failed:
		return
	if not _universe_clock.advance(delta):
		_fail_gate("world clock rejected delta")
		return
	if _waiting:
		# Keep epoch current while loading collision. Move only the temporary,
		# noncontrollable spawn observer; do not reset stable-ready tick count.
		_catalog_frame.advance(0.0)
		_update_terrain_transform()
		_player.global_position = _fixed_to_local(_q0)
		_player.up_direction = _spawn_up()
		_frame.maybe_shift(_player.global_position)
	# In active play the inherited callback calls frame.advance(delta).
	# SharedBodyFrame reads the clock but NEVER advances it again.
	super._physics_process(delta)
	_clock_autosave_s += delta
	if _clock_autosave_s >= 30.0:
		_clock_autosave_s = 0.0
		if not SharedClockStore.save_clock(_clock_universe_id, _universe_clock):
			_fail_gate("world clock autosave failed")


func _process(delta: float) -> void:
	super._process(delta)
	if _clock_ready and _initialised:
		_label.text += "\nWORLD CLOCK %.3f s | no reset on 1/2 | no offline time" % _universe_clock.now_s()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _clock_ready and _initialised:
		if not _save_journal():
			push_error("WorldClock: save on close failed")
