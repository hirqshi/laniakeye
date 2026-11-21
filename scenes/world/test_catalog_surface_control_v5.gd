extends "res://scenes/world/test_catalog_auto_transfer_v4.gd"

const SurfacePolicy5 = preload("res://world/debug/lk_surface_control_policy.gd")
@export var low_gravity_assist_threshold: float = 0.001
@export var assisted_eva_max_speed_mps: float = 5.0
var _control5_assisted: bool = false
var _control5_body: String = ""
var _control5_label: Label
var _control5_log_age: float = 0.0
var _control5_menu_paused: bool = false

func _load_target(index: int) -> void:
	super._load_target(index)
	if not _initialised or _failed:
		return
	_control5_body = String(_context["body"]["id"])
	_control5_assisted = false
	if is_instance_valid(_auto4_ui) and not is_instance_valid(_control5_label):
		_control5_label = Label.new()
		_control5_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_control5_label.add_theme_font_size_override("font_size", 16)
		_control5_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_control5_label.add_theme_constant_override("outline_size", 5)
		_auto4_ui.add_child(_control5_label)
	print("SurfaceControl5: BIND assist_threshold=%.9f max_assist_speed=%.3f normal_landing_unchanged=true" % [low_gravity_assist_threshold, assisted_eva_max_speed_mps])

# All destination-selection paths (menu, brackets, R) pass this method.
func _transfer_log_target() -> void:
	super._transfer_log_target()
	if is_instance_valid(_auto4_panel) and _auto4_panel.visible:
		_auto4_panel.hide()
		Input.mouse_mode = _auto4_old_mouse
		print("SurfaceControl5: MENU selection confirmed; panel closed; automatic processing may resume")

func _control5_gravity_sample() -> Dictionary:
	if not _initialised or not is_instance_valid(_player) or _frame == null or _gravity == null:
		return {"valid": false}
	var point: LkPosition64 = _flight_absolute if _flight_active else _frame.to_absolute(_player.global_position)
	if point == null:
		return {"valid": false}
	var sample: Dictionary = _gravity.sample(point, StringName(_context["body"]["id"]), _player.gravity_switch_ratio)
	var acceleration: Vector3 = sample["acceleration"]
	var magnitude: float = acceleration.length()
	return {"valid": acceleration.is_finite() and is_finite(magnitude), "g": magnitude, "has_up": sample["has_up"], "up": sample["up"], "dominant": sample["dominant_id"]}

func _try_flight_landing() -> void:
	if _control5_assisted:
		_control5_assisted = false
		_flight_landing_requested = false
		_flight_exit_ticks = 0
		_flight_status = "DEBUG FLIGHT restored; still airborne; G near surface selects appropriate control"
		print("SurfaceControl5: EVA_ASSIST_EXIT still_debug_flight=true")
		return
	var sample: Dictionary = _control5_gravity_sample()
	if not sample["valid"]:
		_refuse_flight_landing("gravity sample unavailable; remain in protected Debug Flight")
		return
	var mode: String = SurfacePolicy5.classify(sample["g"], low_gravity_assist_threshold)
	if mode == "INVALID":
		_refuse_flight_landing("invalid gravity/control threshold; no walking transition")
		return
	if mode == "NORMAL":
		super._try_flight_landing()
		return
	# Weak gravity: exit Debug Flight into physical EVA with LkEvaDrive.
	# No hover check, no 5-tick wait, no Assist. Restore player control and physics.
	if _auto_busy or _landing_preparing or is_instance_valid(_pending):
		_refuse_flight_landing("weak gravity: wait for live AUTO terrain; then G enters physical EVA")
		return
	if not _flight_local_terrain_ready():
		_refuse_flight_landing("weak gravity: live nearby terrain not ready; remain in protected flight")
		return
	var up: Vector3 = sample["up"]
	var basis: Basis = _player._basis_from_up(up, _flight_basis)
	_player.global_transform = Transform3D(basis, _player.global_position)
	_player.camera_pivot.transform = _flight_saved_pivot
	_player.player_camera.transform = _flight_saved_camera
	_player.velocity = Vector3.ZERO
	_player.up_direction = up
	_player.dominant_body_id = StringName(_context["body"]["id"])
	_player.collision_layer = 2
	_player.collision_mask = ACTIVE_LAYER
	_player.attach_to_frame(_catalog_frame)
	_player.set_controllable(true)
	_player.set_physics_process(true)
	_player.reset_physics_interpolation()
	_flight_active = false
	_flight_landing_requested = false
	_flight_exit_ticks = 0
	_terrain.visible = true
	_terrain.collision_layer = ACTIVE_LAYER
	_flight_status = "EVA: inertial thrust active; WASD / Space / C; brake decelerates"
	print("SurfaceControl5: EVA_ENTER body=%s g=%.9f has_up=%s physical_flight=true walking_reanchor=false" % [_context["body"]["id"], sample["g"], sample["has_up"]])

func _flight_speed_at_height(height: float, multiplier: float) -> float:
	return super._flight_speed_at_height(height, multiplier)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _initialised or not _context.has("body"):
		return
	var id: String = String(_context["body"]["id"])
	if id != _control5_body:
		_control5_body = id
		_control5_assisted = false
		_control5_log_age = 1.0

func _close_local_world() -> void:
	_control5_assisted = false
	_control5_label = null
	_control5_body = ""
	super._close_local_world()

func _process(delta: float) -> void:
	super._process(delta)
	if not _initialised or not is_instance_valid(_control5_label) or not is_instance_valid(_player):
		return
	var paused: bool = is_instance_valid(_auto4_panel) and _auto4_panel.visible
	if paused != _control5_menu_paused:
		_control5_menu_paused = paused
		print("SurfaceControl5: MENU_PAUSE=%s (Tab/Esc closes; selecting a destination closes automatically)" % paused)
	var mode: String = "DEBUG FLIGHT" if _flight_active else ("PHYSICAL SUPPORTED" if _player.is_on_floor() else "PHYSICAL AIRBORNE")
	if _control5_assisted:
		mode = "EVA ASSIST (stabilized debug control, not inertial zero-g)"
	if _failed:
		mode = "FAILED / PHYSICS STOPPED - inspect error; camera input may remain active"
	var sample: Dictionary = _control5_gravity_sample()
	var floor_state: String = "NOT_SAMPLED_IN_DEBUG" if _flight_active else str(_player.is_on_floor())
	var message: String = "CONTROL: %s | on_floor=%s" % [mode, floor_state]
	if sample["valid"]:
		message += "\ng=%.9f m/s2 | gravity_has_up=%s | weak-control threshold=%.9f" % [sample["g"], sample["has_up"], low_gravity_assist_threshold]
	message += "\nactive=%s | dominant=%s | physical_carrier=%s" % [String(_context["body"]["id"]).left(8), String(_player.dominant_body_id).left(8), String(_player.get("_carrier_id")).left(8)]
	if paused:
		message += "\nAUTO TRANSFER PAUSED: destination menu open - Tab/Esc to close"
	elif _control5_assisted:
		message += "\nWASD + Space/C | wheel reduces speed | G debug cruise | no physical landing/editing in this mode"
	_control5_label.text = message
	_control5_label.modulate = Color(1.0, 0.45, 0.35) if _failed else Color.WHITE
	var view: Vector2 = get_viewport().get_visible_rect().size
	_control5_label.position = Vector2(16.0, maxf(16.0, view.y - _control5_label.get_minimum_size().y - 14.0))
	_control5_log_age += delta
	if _control5_log_age >= 2.0:
		_control5_log_age = 0.0
		if _flight_active or _failed or not _player.is_on_floor():
			print("SurfaceControl5: mode=%s body=%s g=%s on_floor=%s physical_callback=%s" % [mode, _context["body"]["id"], "%.9f" % sample["g"] if sample["valid"] else "INVALID", floor_state, _player.is_physics_processing()])
