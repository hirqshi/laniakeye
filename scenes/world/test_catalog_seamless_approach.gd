extends "res://scenes/world/test_catalog_flight_visuals.gd"

const ApproachForecast = preload("res://game/debug/lk_surface_approach_forecast.gd")

@export var approach_lead_s: float = 60.0
@export var approach_max_height_m: float = 1000000.0
@export var approach_hover_height_m: float = 10000.0
@export var approach_initial_view_m: int = 80
@export var approach_activation_height_m: float = 1024.0
@export var approach_retarget_delay_s: float = 0.75

var _approach_forecast: Dictionary = {}
var _approach_drift_target: LkPosition64
var _approach_drift_s: float = 0.0
var _approach_readiness_us: int = 0
var _approach_max_readiness_us: int = 0
var _approach_first_data: bool = false
var _approach_first_mesh: bool = false
var _approach_forecast_us: int = 0

func _auto_limit() -> float:
	# Staging is near-zero and rotation is forecast, so no full-carry height cap.
	return clampf(approach_max_height_m, 1000.0, 1000000.0)

func _prefetch_activation_height() -> float:
	return clampf(approach_activation_height_m, 128.0, 1500.0)

func _prefetch_surface_target(radius: float) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var q: LkPosition64 = _catalog_frame.inertial_to_body(_flight_absolute)
	if q.length() - radius > _auto_limit() + 2.0:
		_approach_forecast = AutoPolicy.surface_target(q, radius)
		_approach_forecast.merge({"predicted": false, "eta_s": INF})
		return _approach_forecast
	var input_vector: Vector3 = Vector3.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input_vector = Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_SPACE)) - float(Input.is_physical_key_pressed(KEY_C)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if input_vector.length_squared() < 1.0e-12 and _auto_busy:
		_approach_forecast = {"ok": true, "point": _auto_target.copy(), "predicted": false, "eta_s": INF}
		return _approach_forecast
	var direction: Vector3 = (_flight_basis * input_vector).normalized()
	var body_direction: LkPosition64 = _catalog_frame.inertial_to_body(LkPosition64.new(direction.x, direction.y, direction.z))
	var band: Dictionary = FlightCarry.band(radius, float(_context["body"]["surface_gravity_m_s2"]), debug_flight_carry_height_m, debug_flight_adaptive_carry, debug_flight_carry_override_m)
	var boost: float = 4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	_approach_forecast = ApproachForecast.predict(q, body_direction, radius, _catalog_frame.angular_speed_rad_s, _flight_multiplier * boost, band)
	_approach_forecast_us = Time.get_ticks_usec() - started
	return _approach_forecast

func _prefetch_should_start(height: float, closing: float) -> bool:
	if not is_finite(height) or height < 0.5 or height > _auto_limit() + 2.0 or closing < -1.0:
		return false
	if _approach_forecast.get("predicted", false):
		return float(_approach_forecast["eta_s"]) <= maxf(1.0, approach_lead_s) or height <= maxf(64.0, approach_hover_height_m)
	return AutoPolicy.should_start(height, closing, _auto_limit(), maxf(1.0, approach_lead_s), maxf(64.0, approach_hover_height_m))

func _prefetch_target_invalid(target: LkPosition64, height: float) -> bool:
	if height > _auto_limit() * 1.2:
		return true
	var actual: LkPosition64 = AutoPolicy.surface_target(_catalog_frame.inertial_to_body(_flight_absolute), float(_context["body"]["radius_m"]))["point"]
	var clearly_missed: bool = height < 256.0 and not AutoPolicy.in_target(actual, _auto_target, 512.0)
	if not clearly_missed and AutoPolicy.in_target(target, _auto_target, 128.0):
		_approach_drift_s = 0.0
		_approach_drift_target = null
		return false
	if not clearly_missed and (_approach_drift_target == null or not AutoPolicy.in_target(target, _approach_drift_target, 64.0)):
		_approach_drift_target = target.copy()
		_approach_drift_s = 0.0
		return false
	_approach_drift_s += _landing_delta
	return _approach_drift_s >= maxf(0.1, approach_retarget_delay_s)

func _start_auto_surface(target: LkPosition64, height: float, closing: float) -> void:
	_approach_drift_s = 0.0
	_approach_drift_target = null
	_approach_readiness_us = 0
	_approach_max_readiness_us = 0
	_approach_first_data = false
	_approach_first_mesh = false
	var old_view: int = auto_surface_view_distance_m
	auto_surface_view_distance_m = clampi(approach_initial_view_m, 64, 128)
	var started: int = Time.get_ticks_usec()
	super._start_auto_surface(target, height, closing)
	auto_surface_view_distance_m = old_view
	print("ApproachTiming: START predicted=%s eta_s=%.3f setup_cpu_ms=%.3f forecast_cpu_ms=%.3f" % [_approach_forecast.get("predicted", false), float(_approach_forecast.get("eta_s", INF)), float(Time.get_ticks_usec() - started) / 1000.0, float(_approach_forecast_us) / 1000.0])

func _landing_patch_ready() -> bool:
	var started: int = Time.get_ticks_usec()
	var ready: bool = super._landing_patch_ready()
	var elapsed: int = Time.get_ticks_usec() - started
	if _auto_busy:
		_approach_readiness_us += elapsed
		_approach_max_readiness_us = maxi(_approach_max_readiness_us, elapsed)
	return ready

func _poll_auto_surface(delta: float) -> void:
	if is_instance_valid(_pending):
		if not _approach_first_data and _pending.debug_get_data_block_count() > 0:
			_approach_first_data = true
			print("ApproachTiming: FIRST_DATA_BLOCKS seconds=%.3f" % (_auto_elapsed + delta))
		if not _approach_first_mesh and _pending.debug_get_mesh_block_count() > 0:
			_approach_first_mesh = true
			print("ApproachTiming: FIRST_MESH_BLOCKS seconds=%.3f" % (_auto_elapsed + delta))
	super._poll_auto_surface(delta)

func _promote_landing_patch() -> void:
	var was_busy: bool = _auto_busy
	var was_warm: bool = _auto_warm
	super._promote_landing_patch()
	if was_busy and not was_warm and _auto_warm:
		print("ApproachTiming: WARM seconds=%.3f readiness_cpu_total_ms=%.3f readiness_cpu_max_ms=%.3f" % [_auto_elapsed, float(_approach_readiness_us) / 1000.0, float(_approach_max_readiness_us) / 1000.0])
	if was_busy and not _auto_busy:
		print("ApproachTiming: ACTIVE seconds=%.3f readiness_cpu_total_ms=%.3f" % [_auto_elapsed, float(_approach_readiness_us) / 1000.0])

func _process(delta: float) -> void:
	super._process(delta)
	if _initialised and _flight_show_telemetry:
		_label.text += "\nSEAMLESS APPROACH: forecast target | initial view %dm | lead %.0fs | activation %.0fm" % [approach_initial_view_m, approach_lead_s, _prefetch_activation_height()]
