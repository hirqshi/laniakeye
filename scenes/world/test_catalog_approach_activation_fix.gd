extends "res://scenes/world/test_catalog_seamless_approach.gd"

const WarmPolicy = preload("res://world/debug/lk_warm_activation_policy.gd")

@export var activation_recovery_grace_s: float = 0.25
var _warm_follow_actual: bool = false
var _warm_blocked_s: float = 0.0
var _warm_hold_log_s: float = 0.0
var _warm_request_total_s: float = 0.0
var _warm_recenter_count: int = 0
var _warm_recovery_note: String = ""

func _enter_flight() -> void:
	super._enter_flight()
	_warm_follow_actual = false
	_warm_blocked_s = 0.0

func _actual_surface_point() -> LkPosition64:
	return AutoPolicy.surface_target(_catalog_frame.inertial_to_body(_flight_absolute), float(_context["body"]["radius_m"]))["point"]

func _prefetch_surface_target(radius: float) -> Dictionary:
	if _warm_follow_actual:
		var height: float = _flight_absolute.length() - radius
		if height <= _prefetch_activation_height() * 1.5:
			_approach_forecast = AutoPolicy.surface_target(_catalog_frame.inertial_to_body(_flight_absolute), radius)
			_approach_forecast.merge({"predicted": false, "eta_s": INF})
			return _approach_forecast
		_warm_follow_actual = false
	return super._prefetch_surface_target(radius)

func _prefetch_should_start(height: float, closing: float) -> bool:
	if _warm_follow_actual and height >= 0.5 and height <= _prefetch_activation_height() and closing >= -1.0:
		return true
	return super._prefetch_should_start(height, closing)

func _prefetch_target_invalid(target: LkPosition64, height: float) -> bool:
	if _auto_busy and height <= _prefetch_activation_height():
		var actual: LkPosition64 = _actual_surface_point()
		if _auto_warm or _warm_follow_actual:
			# Let recovery handle nearby warm misses instead of applying the
			# forecast retention rule to a different (actual-footpoint) criterion.
			_warm_follow_actual = true
			if WarmPolicy.reusable(actual, _pending_anchor):
				return false
			_warm_recovery_note = "actual footpoint outside reusable anchor region"
			return true
	return super._prefetch_target_invalid(target, height)

func _start_auto_surface(target: LkPosition64, height: float, closing: float) -> void:
	_warm_request_total_s = 0.0
	_warm_recenter_count = 0
	_warm_blocked_s = 0.0
	_warm_hold_log_s = 0.0
	_warm_recovery_note = ""
	super._start_auto_surface(target, height, closing)

func _poll_auto_surface(delta: float) -> void:
	if not _auto_busy or not is_instance_valid(_pending):
		super._poll_auto_surface(delta)
		return
	_warm_request_total_s += delta
	_warm_hold_log_s += delta
	var height: float = _flight_absolute.length() - float(_context["body"]["radius_m"])
	var actual: LkPosition64 = _actual_surface_point()
	var gap: float = actual.minus(_auto_target).length()
	if _auto_warm and height <= _prefetch_activation_height() and gap > WarmPolicy.ACTIVATE_GAP_M:
		_warm_blocked_s += delta
	else:
		_warm_blocked_s = 0.0
	if _auto_warm:
		var decision: String = WarmPolicy.action(height, gap, WarmPolicy.reusable(actual, _pending_anchor), _prefetch_activation_height(), _warm_blocked_s, activation_recovery_grace_s)
		if _warm_hold_log_s >= 2.0:
			_warm_hold_log_s = 0.0
			print("ActivationGuard: %s total_s=%.2f height_m=%.3f target_gap_m=%.3f anchor_gap_m=%.3f limit_m=%.1f aligned=%s" % [decision, _warm_request_total_s, height, gap, actual.minus(_pending_anchor).length(), _prefetch_activation_height(), _auto_aligning])
		if decision == "RECENTER":
			_recenter_warm_patch(actual, height, gap)
		elif decision == "RETARGET" or decision == "INVALID":
			_warm_follow_actual = true
			_warm_recovery_note = "warm activation recovery: " + decision
			_cancel_landing_patch(_warm_recovery_note)
			_auto_retry_s = minf(_auto_retry_s, 0.5)
			return
		# Counter reflects five successful checks, not thousands of fake goals.
		_pending_stable_ticks = mini(_pending_stable_ticks, 4)
	super._poll_auto_surface(delta)
	if _auto_busy:
		_pending_stable_ticks = mini(_pending_stable_ticks, 5)
		if _auto_warm and not _auto_aligning:
			var current_height: float = _flight_absolute.length() - float(_context["body"]["radius_m"])
			var current_gap: float = _actual_surface_point().minus(_auto_target).length()
			_flight_status = "Terrain READY | height %.1f / %.1f m | actual target gap %.1f / 48 m" % [current_height, _prefetch_activation_height(), current_gap]

func _recenter_warm_patch(actual: LkPosition64, height: float, gap: float) -> void:
	var previous_elapsed: float = _auto_elapsed
	_warm_follow_actual = true
	_auto_target = actual.copy()
	_auto_aligning = false
	_auto_align_s = 0.0
	_auto_warm = false
	_pending_stable_ticks = 0
	_warm_blocked_s = 0.0
	_warm_recenter_count += 1
	# Start a new readiness epoch with the SAME generator/anchor/journal. The
	# timeout must not inherit an earlier legitimate high-altitude wait.
	_auto_elapsed = 0.0
	_pending_time_s = 0.0
	_auto_first_collider_s = -1.0
	_auto_last_stage = ""
	_landing_stage = "RECENTER REVALIDATION"
	_approach_drift_s = 0.0
	_approach_drift_target = null
	_update_terrain_transform()
	print("ActivationGuard: RECENTER epoch=%d previous_epoch_s=%.3f request_total_s=%.3f height_m=%.3f old_gap_m=%.3f anchor_retained=true generator_retained=true" % [_warm_recenter_count, previous_elapsed, _warm_request_total_s, height, gap])

func _landing_patch_ready() -> bool:
	var ready: bool = super._landing_patch_ready()
	if ready and _auto_busy and _auto_warm and not _auto_aligning:
		var height: float = _flight_absolute.length() - float(_context["body"]["radius_m"])
		var gap: float = _actual_surface_point().minus(_auto_target).length()
		if height > _prefetch_activation_height():
			_landing_stage = "READY WAITING APPROACH HEIGHT"
		elif gap > WarmPolicy.ACTIVATE_GAP_M:
			_landing_stage = "READY RECENTERING ACTUAL FOOTPOINT"
	return ready

func _cancel_landing_patch(reason: String) -> void:
	var enriched: String = reason
	if _auto_busy:
		var height: float = _flight_absolute.length() - float(_context["body"]["radius_m"])
		var gap: float = _actual_surface_point().minus(_auto_target).length()
		enriched += " | height=%.2f actual_gap=%.2f warm=%s" % [height, gap, _auto_warm]
		if _warm_recovery_note != "":
			enriched += " | " + _warm_recovery_note
	super._cancel_landing_patch(enriched)

func _promote_landing_patch() -> void:
	var was_busy: bool = _auto_busy
	super._promote_landing_patch()
	if was_busy and not _auto_busy:
		print("ActivationGuard: ACTIVE request_total_s=%.3f recenters=%d" % [_warm_request_total_s, _warm_recenter_count])

func _process(delta: float) -> void:
	super._process(delta)
	if _initialised and _flight_show_telemetry:
		_label.text += "\nACTIVATION GUARD: ready != loading | near-surface footpoint recovery enabled"
