extends "res://scenes/world/test_catalog_transfer_handover_v2.gd"

const TransferRouteBook3 = preload("res://game/debug/lk_transfer_route_book.gd")
var _route_book = TransferRouteBook3.new()
var _route_status: String = "R selects previous departure; 1/2 disabled"
var _route_bearing: String = ""
var _route_hud_s: float = 1.0
var _route_audit_blocked: bool = false

# Record expectations only AFTER existing body/clock persistence succeeds.
func _save_journal() -> bool:
	if _route_audit_blocked:
		push_error("Transfer3: journal write blocked after return-audit failure; stop and inspect")
		return false
	if not super._save_journal():
		return false
	if not _context.has("body") or not is_instance_valid(_edit_journal):
		return false
	if not _route_book.note_saved(String(_context["body"]["id"]), _edit_journal.get_revision(), _edit_journal.copy_records()):
		_route_audit_blocked = true
		_fail_gate("Transfer3 cannot record persistence expectation after save")
		return false
	return true

func _handover() -> void:
	var from_id: String = String(_context["body"]["id"])
	super._handover()
	if _failed or not _context.has("body"):
		return
	var to_id: String = String(_context["body"]["id"])
	if from_id == to_id:
		return
	_route_book.note_transition(from_id, to_id)
	_route_hud_s = 1.0
	var audit: Dictionary = _route_book.check_arrival(to_id, _edit_journal.get_revision(), _edit_journal.copy_records())
	if audit["known"]:
		if not audit["match"]:
			_route_audit_blocked = true
			_route_status = "RETURN AUDIT FAILED; journal writes blocked; stop and inspect"
			print("Transfer3: RETURN_AUDIT FAIL body=%s expected_revision=%d actual_revision=%d" % [to_id, audit["expected_revision"], audit["actual_revision"]])
			_fail_gate("Transfer3 return journal differs from last successful save")
			return
		_route_status = "RETURN AUDIT PASS: revision and all saved edit records match"
		print("Transfer3: RETURN_AUDIT PASS body=%s revision=%d records_sha256_match=true" % [to_id, _edit_journal.get_revision()])
	else:
		_route_status = "First arrival this session; no previous save expectation"
		print("Transfer3: ARRIVAL body=%s revision=%d audit=NO_PRIOR_SESSION_SAVE" % [to_id, _edit_journal.get_revision()])
	print("Transfer3: ROUTE transitions=%d return_target=%s active=%s" % [_route_book.transitions, _route_book.return_id, to_id])

func _route_select_return() -> void:
	if _route_book.return_id.is_empty():
		_route_status = "No previous departure yet; perform first Ctrl+Enter handover"
		return
	for index: int in range(_transfer_model.entries.size()):
		if _transfer_model.entries[index]["id"] != _route_book.return_id:
			continue
		_transfer_cancel("return target selected", false)
		_transfer_model.selected = index
		_transfer_hud_s = 1.0
		_route_hud_s = 1.0
		_route_status = "Return destination selected; physically fly, F prepare, Ctrl+Enter"
		_transfer_log_target()
		print("Transfer3: SELECT_RETURN target=%s active_unchanged=%s" % [_route_book.return_id, _context["body"]["id"]])
		return
	_route_status = "Previous departure absent from current target catalogue"

func _route_update_bearing() -> void:
	var entry: Dictionary = _transfer_model.current()
	if entry.is_empty():
		_route_bearing = "No destination"
		return
	var active_id: String = String(_context["body"]["id"])
	if entry["id"] == active_id:
		_route_bearing = "Selected body is ACTIVE; choose destination with [ / ] or R"
		return
	var observer: LkPosition64 = _flight_absolute if _flight_active else _frame.to_absolute(_player.player_camera.global_position)
	var states: Dictionary = _flight_system_states()
	if states.get("system_id", "") != _nav_layout["system_id"]:
		_route_bearing = "Destination state scope unavailable"
		return
	var result: Dictionary = TransferFrameMath2.rebase(states, active_id, entry["id"], observer, _universe_clock.now_s())
	if not result["ok"]:
		_route_bearing = "Destination state unavailable"
		return
	var offset: LkPosition64 = result["observer"]
	var distance: float = offset.length()
	if not is_finite(distance) or distance <= 0.0:
		_route_bearing = "Destination direction undefined"
		return
	# Only a UNIT direction enters Vector3; all astronomical offsets stay double.
	var direction: Vector3 = Vector3(-offset.x / distance, -offset.y / distance, -offset.z / distance)
	var local: Vector3 = _player.player_camera.global_basis.inverse() * direction
	var yaw: float = rad_to_deg(atan2(local.x, -local.z))
	var pitch: float = rad_to_deg(atan2(local.y, sqrt(local.x * local.x + local.z * local.z)))
	var height: float = distance - float(entry["body"]["radius_m"])
	_route_bearing = "Target bearing yaw %+.1f deg (right+) pitch %+.1f deg (up+) | surface %s" % [yaw, pitch, NavData.distance_text(height)]
	_route_bearing += " | reference window: 10..2000 km above target"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1, KEY_2]:
			_route_status = "Legacy 1/2 blocked: use physical flight and Ctrl+Enter"
			print("Transfer3: LEGACY_SWITCH_BLOCKED key=%s" % event.keycode)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_R and not event.alt_pressed and not event.ctrl_pressed and not event.shift_pressed and _initialised and not _failed:
			_route_select_return()
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)

func _process(delta: float) -> void:
	super._process(delta)
	if not _initialised or _failed:
		return
	_route_hud_s += delta
	if _route_hud_s >= 0.2 and not _waiting:
		_route_hud_s = 0.0
		_route_update_bearing()
	_label.text += "\nTRANSFER3: R select return | 1/2 blocked | handovers %d" % _route_book.transitions
	_label.text += "\n" + _route_status + "\n" + _route_bearing
