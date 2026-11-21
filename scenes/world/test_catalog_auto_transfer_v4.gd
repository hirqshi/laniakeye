extends "res://scenes/world/test_catalog_transfer_roundtrip_v3.gd"

const AutoTransferPolicy4 = preload("res://world/debug/lk_auto_transfer_policy.gd")
const TargetPointer4 = preload("res://world/debug/lk_transfer_target_pointer.gd")
@export var auto_transfer_enabled: bool = true
var _auto4_guard_epoch: float = NAN
var _auto4_guard_target: String = ""
var _auto4_request_in_progress: bool = false
var _auto4_prepare_pending: bool = false
var _auto4_retry: float = 0.0
var _auto4_cooldown: float = 0.0
var _auto4_select_timer: float = 0.0
var _auto4_selected: String = ""
var _auto4_active: String = ""
var _auto4_reason: String = ""
var _auto4_ui: CanvasLayer
var _auto4_panel: PanelContainer
var _auto4_planets: OptionButton
var _auto4_list: ItemList
var _auto4_check: CheckButton
var _auto4_pointer: TargetPointer4
var _auto4_parent_slot: int = 0
var _auto4_list_rows: Array[Dictionary] = []
var _auto4_ui_sync: bool = false
var _auto4_ui_age: float = 1.0
var _auto4_old_mouse: int = Input.MOUSE_MODE_CAPTURED

func _load_target(index: int) -> void:
	super._load_target(index)
	if not _initialised or _failed:
		return
	_auto4_active = String(_context["body"]["id"])
	_auto4_parent_slot = int(_context["address"]["planet_slot"])
	_auto4_create_ui()
	print("AutoTransfer4: BIND auto-nearest=true full_step_entry_guard=true auto=%s" % auto_transfer_enabled)

func _transfer_log_target() -> void:
	super._transfer_log_target()
	var entry: Dictionary = _transfer_model.current()
	if entry.is_empty():
		return
	if _auto4_selected != entry["id"]:
		_auto4_selected = entry["id"]
		_auto4_guard_epoch = NAN
		_auto4_guard_target = ""
		_auto4_retry = 0.0
		_auto4_prepare_pending = false
		_auto4_reason = ""
	_auto4_parent_slot = int(entry["planet_slot"])
	_auto4_ui_age = 1.0
	_auto4_sync_parent()

func _auto4_geometry() -> Dictionary:
	var entry: Dictionary = _transfer_model.current()
	if entry.is_empty() or entry["id"] == _context["body"]["id"]:
		return {"ok": false}
	var epoch: float = _universe_clock.now_s()
	var states: Dictionary = _flight_system_states()
	if states.get("system_id", "") != _nav_layout["system_id"]:
		return {"ok": false}
	var observer: LkPosition64 = _flight_absolute if _flight_active else _frame.to_absolute(_player.player_camera.global_position)
	var result: Dictionary = TransferFrameMath2.rebase(states, String(_context["body"]["id"]), entry["id"], observer, epoch)
	if not result["ok"]:
		return result
	var offset: LkPosition64 = result["observer"]
	var distance: float = offset.length()
	var radius: float = float(entry["body"]["radius_m"])
	if not is_finite(distance) or distance <= 0.0 or not is_finite(radius) or radius <= 0.0:
		return {"ok": false}
	var limits: Dictionary = AutoTransferPolicy4.heights(radius)
	return {"ok": true, "entry": entry, "epoch": epoch, "offset": offset, "distance": distance,
		"height": distance - radius, "source_height": observer.length() - float(_context["body"]["radius_m"]),
		"radius": radius, "switch": limits["switch_m"], "prepare": limits["prepare_m"]}

# Automatic nearest non-active destination, re-evaluated periodically.
func _auto4_select_nearest() -> void:
	var active_id: String = String(_context["body"]["id"])
	var observer: LkPosition64 = _flight_absolute if _flight_active else _frame.to_absolute(_player.player_camera.global_position)
	var states: Dictionary = _flight_system_states()
	if states.get("system_id", "") != _nav_layout["system_id"]:
		return
	var best_index: int = -1
	var best_distance: float = INF
	var epoch: float = _universe_clock.now_s()
	for index: int in range(_transfer_model.entries.size()):
		var entry: Dictionary = _transfer_model.entries[index]
		if entry["id"] == active_id:
			continue
		var result: Dictionary = TransferFrameMath2.rebase(states, active_id, entry["id"], observer, epoch)
		if not result["ok"]:
			continue
		var distance: float = result["observer"].length()
		if not is_finite(distance) or distance <= 0.0:
			continue
		if distance < best_distance:
			best_distance = distance
			best_index = index
	if best_index < 0:
		return
	var current: Dictionary = _transfer_model.current()
	if not current.is_empty() and current["id"] == _transfer_model.entries[best_index]["id"]:
		return
	_transfer_cancel("auto nearest destination", false)
	_transfer_model.selected = best_index
	_transfer_hud_s = 1.0
	_transfer_log_target()

# Preserve ALL ancestor spheres (including current-body approach guard), then
# append one selected-target entry guard. Original safe_step consumes full array.
# Flight-only: in EVA the player moves via physics, no bounded-step guard.
func _flight_spheres() -> Array:
	_auto4_guard_epoch = NAN
	_auto4_guard_target = ""
	var spheres: Array = super._flight_spheres()
	if _failed or not auto_transfer_enabled or not _flight_active:
		return spheres
	var geometry: Dictionary = _auto4_geometry()
	if not geometry["ok"] or geometry["source_height"] < HANDOVER_MIN_HEIGHT_M:
		return spheres
	spheres.append(AutoTransferPolicy4.entry_guard(geometry["offset"], geometry["radius"]))
	_auto4_guard_epoch = geometry["epoch"]
	_auto4_guard_target = geometry["entry"]["id"]
	return spheres

# Automatic handover is valid after THIS epoch's guard (flight sphere guard or
# EVA direct guard set in _physics_process). Parent checks heights/errors/etc.
func _handover_motion_allowed() -> bool:
	if not _auto4_request_in_progress:
		return super._handover_motion_allowed()
	var geometry: Dictionary = _auto4_geometry()
	return geometry["ok"] and _auto4_guard_epoch == _universe_clock.now_s() and _auto4_guard_target == geometry["entry"]["id"] and geometry["source_height"] >= HANDOVER_MIN_HEIGHT_M and geometry["height"] >= HANDOVER_MIN_HEIGHT_M and geometry["height"] <= HANDOVER_MAX_HEIGHT_M

func _auto4_wait(reason: String) -> void:
	if reason != _auto4_reason:
		_auto4_reason = reason
		print("AutoTransfer4: " + reason)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _initialised or _failed or _waiting:
		return
	var active: String = String(_context["body"]["id"])
	if active != _auto4_active:
		_auto4_active = active
		_auto4_cooldown = 2.0
		_auto4_guard_epoch = NAN
		_auto4_ui_age = 1.0
	_auto4_cooldown = maxf(0.0, _auto4_cooldown - delta)
	_auto4_retry = maxf(0.0, _auto4_retry - delta)
	if not auto_transfer_enabled or _auto4_cooldown > 0.0:
		return
	if is_instance_valid(_auto4_panel) and _auto4_panel.visible:
		return
	_auto4_select_timer -= delta
	if _auto4_select_timer <= 0.0:
		_auto4_select_timer = 0.5
		_auto4_select_nearest()
	var geometry: Dictionary = _auto4_geometry()
	if not geometry["ok"]:
		return
	if geometry["source_height"] < HANDOVER_MIN_HEIGHT_M:
		_auto4_wait("WAIT source altitude >=10km")
		return
	if geometry["height"] > geometry["prepare"]:
		return
	if not auto_surface_enabled or not cpu3_optimizations_enabled or not cpu3_share_system_states or not cpu4_optimizations_enabled:
		_auto4_wait("WAIT enable AUTO/CPU3 sharing/CPU4, or disable auto transfer in Tab menu")
		return
	if _auto_busy or _landing_preparing or is_instance_valid(_pending) or _movement_paused or _stream_hold:
		_auto4_wait("WAIT source publication/preparation")
		return
	var target_id: String = geometry["entry"]["id"]
	if not is_instance_valid(_transfer_viewport) or _transfer_body_id != target_id:
		if _auto4_retry <= 0.0:
			_transfer_request = true
			_auto4_prepare_pending = true
			_auto4_retry = 2.0
			_auto4_wait("AUTO PREPARE target=" + target_id)
		return
	if not _transfer_warm:
		_auto4_wait("WAIT target preparation; entry guard holds inward motion if needed")
		return
	if _auto4_prepare_pending:
		_auto4_prepare_pending = false
		_auto4_retry = 0.0
	if geometry["height"] > geometry["switch"] + 1.0:
		return
	if geometry["height"] < HANDOVER_MIN_HEIGHT_M:
		_auto4_wait("WAIT target too close for V2 handover; fly outward above10km")
		return
	if _auto4_retry > 0.0:
		return
	# EVA has no flight sphere guard; set the guard for this tick directly.
	_auto4_guard_epoch = geometry["epoch"]
	_auto4_guard_target = target_id
	_auto4_request_in_progress = true
	var from_id: String = active
	super._handover()
	_auto4_request_in_progress = false
	_auto4_retry = 1.0
	if _failed:
		return
	if String(_context["body"]["id"]) != from_id:
		_auto4_active = String(_context["body"]["id"])
		_auto4_cooldown = 2.0
		_auto4_guard_epoch = NAN
		_auto4_wait("AUTO ACTIVE from=%s to=%s" % [from_id, _auto4_active])
	else:
		_auto4_wait("WAIT " + _handover_status)
		if _handover_status.contains("revision changed"):
			_transfer_cancel("revision changed; auto rebuild", false)

func _auto4_create_ui() -> void:
	if is_instance_valid(_auto4_ui):
		return
	_auto4_ui = CanvasLayer.new()
	_auto4_ui.layer = 40
	add_child(_auto4_ui)
	_auto4_pointer = TargetPointer4.new()
	_auto4_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_auto4_pointer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_auto4_ui.add_child(_auto4_pointer)
	_auto4_panel = PanelContainer.new()
	_auto4_panel.custom_minimum_size = Vector2(380, 350)
	_auto4_ui.add_child(_auto4_panel)
	var column: VBoxContainer = VBoxContainer.new()
	_auto4_panel.add_child(column)
	var title: Label = Label.new()
	title.text = "DESTINATION | Tab closes | [ / ] cycle family"
	column.add_child(title)
	_auto4_check = CheckButton.new()
	_auto4_check.text = "Automatic target preparation and handover"
	_auto4_check.button_pressed = auto_transfer_enabled
	_auto4_check.toggled.connect(_auto4_toggle)
	column.add_child(_auto4_check)
	_auto4_planets = OptionButton.new()
	for index: int in range(_nav_layout["planets"].size()):
		var body: Dictionary = _nav_layout["planets"][index]["body"]
		var slot: int = int(body.get("slot", index))
		_auto4_planets.add_item("Planet %02d%s" % [slot + 1, " (gas giant: moons only)" if body["family"] == "gas_giant" else ""], slot)
	_auto4_planets.item_selected.connect(_auto4_parent_changed)
	column.add_child(_auto4_planets)
	var home: Button = Button.new()
	home.text = "Show active planet's family"
	home.pressed.connect(_auto4_home_family)
	column.add_child(home)
	_auto4_list = ItemList.new()
	_auto4_list.custom_minimum_size = Vector2(370, 240)
	_auto4_list.item_selected.connect(_auto4_pick_row)
	column.add_child(_auto4_list)
	_auto4_panel.hide()
	_auto4_sync_parent()

func _auto4_toggle(enabled: bool) -> void:
	auto_transfer_enabled = enabled
	_auto4_guard_epoch = NAN
	_auto4_reason = ""
	print("AutoTransfer4: enabled=%s" % enabled)

func _auto4_sync_parent() -> void:
	if not is_instance_valid(_auto4_planets):
		return
	_auto4_ui_sync = true
	for index: int in range(_auto4_planets.item_count):
		if _auto4_planets.get_item_id(index) == _auto4_parent_slot:
			_auto4_planets.select(index)
			break
	_auto4_ui_sync = false

func _auto4_parent_changed(index: int) -> void:
	if _auto4_ui_sync:
		return
	_auto4_parent_slot = _auto4_planets.get_item_id(index)
	_auto4_ui_age = 1.0
	_auto4_refresh_rows()

func _auto4_home_family() -> void:
	_auto4_parent_slot = int(_context["address"]["planet_slot"])
	_auto4_sync_parent()
	_auto4_refresh_rows()

func _auto4_refresh_rows() -> void:
	if not _initialised or _waiting or not is_instance_valid(_auto4_list):
		return
	var observer: LkPosition64 = _flight_absolute if _flight_active else _frame.to_absolute(_player.player_camera.global_position)
	_auto4_list_rows = AutoTransferPolicy4.rows(_transfer_model.entries, _auto4_parent_slot, _flight_system_states(), String(_context["body"]["id"]), observer)
	_auto4_ui_sync = true
	_auto4_list.clear()
	for index: int in range(_auto4_list_rows.size()):
		var row: Dictionary = _auto4_list_rows[index]
		_auto4_list.add_item("%s%s | %s" % [row["label"], " [ACTIVE]" if row["active"] else "", NavData.distance_text(row["gap"])])
		if row["index"] == _transfer_model.selected:
			_auto4_list.select(index)
	_auto4_ui_sync = false

func _auto4_pick_row(index: int) -> void:
	if _auto4_ui_sync or index < 0 or index >= _auto4_list_rows.size():
		return
	_transfer_cancel("destination changed", false)
	_transfer_model.selected = int(_auto4_list_rows[index]["index"])
	_transfer_hud_s = 1.0
	_transfer_log_target()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and not event.alt_pressed and not event.ctrl_pressed and not event.shift_pressed:
		if event.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT] and _initialised and not _failed:
			_auto4_refresh_rows()
			if not _auto4_list_rows.is_empty():
				var position: int = -1
				for index: int in range(_auto4_list_rows.size()):
					if _auto4_list_rows[index]["index"] == _transfer_model.selected:
						position = index
						break
				var step: int = -1 if event.keycode == KEY_BRACKETLEFT else 1
				_auto4_pick_row(posmod(position + step, _auto4_list_rows.size()))
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)

func _close_local_world() -> void:
	_auto4_ui = null
	_auto4_panel = null
	_auto4_planets = null
	_auto4_list = null
	_auto4_pointer = null
	_auto4_guard_epoch = NAN
	_auto4_request_in_progress = false
	super._close_local_world()

func _process(delta: float) -> void:
	super._process(delta)
	if not _initialised or _failed or _waiting or not is_instance_valid(_auto4_pointer):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_auto4_pointer.size = viewport_size
	_auto4_panel.position = Vector2(maxf(8.0, viewport_size.x - 400.0), 12.0)
	_auto4_ui_age += delta
	if _auto4_ui_age >= 0.25:
		_auto4_ui_age = 0.0
		if _auto4_panel.visible:
			_auto4_refresh_rows()
		var geometry: Dictionary = _auto4_geometry()
		if geometry["ok"]:
			var offset: LkPosition64 = geometry["offset"]
			var direction: Vector3 = Vector3(-offset.x / geometry["distance"], -offset.y / geometry["distance"], -offset.z / geometry["distance"])
			_auto4_pointer.set_meta("direction", direction)
			_auto4_pointer.caption = "%s | %s" % [geometry["entry"]["label"], NavData.distance_text(geometry["height"]) ]
			_auto4_pointer.blocked = _nav_occluded([-offset.x, -offset.y, -offset.z], geometry["distance"], geometry["entry"]["id"])
		elif _auto4_pointer.has_meta("direction"):
			_auto4_pointer.remove_meta("direction")
	if _auto4_pointer.has_meta("direction"):
		_auto4_pointer.projection = NavData.project_direction(_player.player_camera, _auto4_pointer.get_meta("direction"), viewport_size)
	else:
		_auto4_pointer.projection = {}
	_auto4_pointer.queue_redraw()
	_label.text += "\nAUTO TRANSFER4 %s | auto nearest target, flight+EVA handovers" % auto_transfer_enabled
	_label.text += "\n" + _auto4_reason

# Tab must be handled before Control focus navigation consumes it.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.alt_pressed or event.ctrl_pressed or event.shift_pressed or not is_instance_valid(_auto4_panel):
		return
	if event.keycode != KEY_TAB and not (event.keycode == KEY_ESCAPE and _auto4_panel.visible):
		return
	if _auto4_panel.visible:
		_auto4_panel.hide()
		Input.mouse_mode = _auto4_old_mouse
	else:
		_auto4_old_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_auto4_panel.show()
		_auto4_refresh_rows()
	get_viewport().set_input_as_handled()
