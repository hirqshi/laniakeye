extends "res://scenes/world/test_catalog_surface_contact_v6.gd"

# EVA_TERRAIN_V7
# Debug Flight used to be the only owner of terrain provisioning: AutoSurface ran
# inside _tick_flight, and only flight re-enabled a handed-over terrain. Physical
# EVA therefore never prepared terrain, and stale pause/hold flags left behind by
# EVA blocked both G (Debug Flight) and automatic handover. This layer removes
# those couplings without changing the validated walking reanchor.

const EVA_GATE_HEIGHT_M: float = 4096.0
const EVA_GATE_ANCHOR_M: float = 8192.0


func _release_stale_state() -> void:
	_stream_hold = false
	_stream_hold_reason = ""
	_stream_good_ticks = 0
	_stream_hold_s = 0.0
	_stream_warned = false
	if _movement_paused and not is_instance_valid(_pending):
		_movement_paused = false


# Debug Flight is the recovery tool; EVA state must never be able to veto it.
func _enter_flight() -> void:
	if not _waiting:
		if is_instance_valid(_pending) and not _auto_busy and not _landing_preparing:
			_cancel_pending_patch("Debug Flight entered")
		_release_stale_state()
	super._enter_flight()


func _exit_flight_direct() -> void:
	super._exit_flight_direct()
	_release_stale_state()


# AutoSurface owns its staging patch; the walking loop must not pause the player,
# time it out, or try to commit its sandbox.
func _walk_reanchor_blocked() -> bool:
	return _auto_busy or _landing_preparing


func _restore_eva_viewer() -> void:
	# Flight turns the player's viewer off while staging. A physical player
	# needs live collisions under it at all times.
	if is_instance_valid(_flight_viewer):
		_flight_viewer.requires_visuals = true
		_flight_viewer.requires_collisions = true


func _start_auto_surface(target: LkPosition64, height: float, closing: float) -> void:
	super._start_auto_surface(target, height, closing)
	if not _flight_active:
		_restore_eva_viewer()


func _update_terrain_transform() -> void:
	super._update_terrain_transform()
	if _flight_active or not _initialised or not is_instance_valid(_player):
		return
	_restore_eva_viewer()
	_eva_terrain_gate()


# Same near-patch rule Debug Flight applies, so a handed-over or flight-disabled
# terrain becomes live for EVA too. Enable near the player; hide and disable
# collisions when the player has moved away. This mirrors Flight's near/far
# behaviour without destroying a handed-over patch.
func _eva_terrain_gate() -> void:
	if not is_instance_valid(_terrain) or _frame == null or _catalog_frame == null or not _context.has("body"):
		return
	var absolute: LkPosition64 = _frame.to_absolute(_player.global_position)
	var height: float = absolute.length() - float(_context["body"]["radius_m"])
	var near: bool = height < EVA_GATE_HEIGHT_M and _catalog_frame.inertial_to_body(absolute).minus(_anchor).length() < EVA_GATE_ANCHOR_M
	if near:
		if not _terrain.visible:
			_terrain.visible = true
		if _terrain.collision_layer != ACTIVE_LAYER:
			_terrain.collision_layer = ACTIVE_LAYER
	else:
		if _terrain.visible:
			_terrain.visible = false
		if _terrain.collision_layer != 0:
			_terrain.collision_layer = 0


# EVA has no flight basis or input forecast; use the actual footpoint.
func _prefetch_surface_target(radius: float) -> Dictionary:
	if _flight_active:
		return super._prefetch_surface_target(radius)
	var result: Dictionary = AutoPolicy.surface_target(_catalog_frame.inertial_to_body(_flight_absolute), radius)
	result.merge({"predicted": false, "eta_s": INF})
	_approach_forecast = result
	return result


func _promote_landing_patch() -> void:
	var was_busy: bool = _auto_busy
	super._promote_landing_patch()
	if was_busy and not _auto_busy:
		# The AutoSurface path never released the walking pause.
		_movement_paused = false
		if not _flight_active and not _failed and is_instance_valid(_player):
			_player.set_physics_process(true)


# Open space has no nearby terrain to stream. The inherited guard would freeze
# EVA there, while Flight skips the guard entirely — which is why switching to
# Debug Flight used to "unfreeze" and load terrain.
func _eva_open_space() -> bool:
	if not is_instance_valid(_player) or not _context.has("body") or _frame == null or _catalog_frame == null:
		return false
	var absolute: LkPosition64 = _frame.to_absolute(_player.global_position)
	var height: float = absolute.length() - float(_context["body"]["radius_m"])
	if height >= EVA_GATE_HEIGHT_M:
		return true
	return _catalog_frame.inertial_to_body(absolute).minus(_anchor).length() >= EVA_GATE_ANCHOR_M


func _update_stream_guard(delta: float) -> bool:
	# While AutoSurface is preparing its staging patch, the player is airborne
	# and the live terrain under them is intentionally not ready yet. The
	# inherited guard would set _stream_hold and disable player physics — the
	# EVA freeze. Flight skips this guard in _tick_flight, which is why it does
	# not freeze. Let EVA keep flying; terrain activation still gates walking.
	if not _flight_active and (_auto_busy or _landing_preparing):
		if _stream_hold:
			_release_stale_state()
		return true
	if not _flight_active and _eva_open_space():
		if _stream_hold:
			_release_stale_state()
		return true
	return super._update_stream_guard(delta)


func _physics_process(delta: float) -> void:
	# A pause flag without a pending patch is stale and blocks handover.
	if _movement_paused and not is_instance_valid(_pending) and not _failed:
		if _flight_active:
			_movement_paused = false
		else:
			_resume_movement()
	super._physics_process(delta)
	if not _initialised or _failed or _waiting or _flight_active or _contact6_active:
		return
	_eva_surface_tick(delta)


# Mirror of the AutoSurface block in _tick_flight, for physical EVA. A player
# standing on the floor keeps the validated walking reanchor instead.
func _eva_surface_tick(delta: float) -> void:
	if not auto_surface_enabled or not is_instance_valid(_player) or not _context.has("body"):
		return
	if _player.is_on_floor() and not _auto_busy:
		return
	_landing_delta = delta
	_flight_absolute = _frame.to_absolute(_player.global_position)
	_auto_retry_s = maxf(0.0, _auto_retry_s - delta)
	_auto_retarget_s = maxf(0.0, _auto_retarget_s - delta)
	var radius: float = float(_context["body"]["radius_m"])
	var height: float = _flight_absolute.length() - radius
	var closing: float = 0.0
	if is_finite(_auto_last_height):
		closing = (_auto_last_height - height) / delta
	_auto_last_height = height
	var target_result: Dictionary = _prefetch_surface_target(radius)
	if not target_result["ok"]:
		return
	var target: LkPosition64 = target_result["point"]
	if _auto_busy:
		# Continue the already-started EVA staging every tick. The previous
		# early return stopped _poll_auto_surface, so the patch never became
		# active and could not be edited in EVA.
		if _prefetch_target_invalid(target, height):
			if height <= _auto_limit() and closing > 0.0 and _auto_retarget_s <= 0.0:
				_cancel_landing_patch("retarget for new approach point")
				_auto_retarget_s = 0.5
				_auto_candidate = target
				_auto_candidate_s = auto_surface_stable_target_s
				_start_auto_surface(target, height, closing)
				return
			_cancel_landing_patch("left target region")
			return
		_poll_auto_surface(delta)
		return
	if is_instance_valid(_pending):
		# A walk-reanchor staging patch shares _pending. Do not overwrite it;
		# wait for it to complete before starting EVA AutoSurface.
		return
	if _auto_target != null and is_instance_valid(_auto_viewer) and AutoPolicy.in_target(target, _auto_target, 48.0):
		return
	if AutoPolicy.in_target(target, _anchor, 64.0) and _flight_local_terrain_ready():
		return
	if _auto_retry_s > 0.0 or not _prefetch_should_start(height, closing):
		_auto_candidate_s = 0.0
		_auto_candidate = null
		return
	if _auto_candidate == null or not AutoPolicy.in_target(target, _auto_candidate, 32.0):
		_auto_candidate = target
		_auto_candidate_s = 0.0
		return
	_auto_candidate_s += delta
	if _auto_candidate_s >= maxf(0.0, auto_surface_stable_target_s):
		_start_auto_surface(target, height, closing)
