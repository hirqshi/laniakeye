extends SceneTree

const Book3 = preload("res://world/debug/lk_transfer_route_book.gd")
const Scene3 = preload("res://scenes/world/test_catalog_transfer_roundtrip_v3.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("Transfer3: FAIL " + label)

func _initialize() -> void:
	var book = Book3.new()
	var a_records: PackedFloat64Array = PackedFloat64Array([1.125, 2.25, 3.5, 2.0, 0.0])
	var b_records: PackedFloat64Array = PackedFloat64Array([10.0, 20.0, 30.0, 2.0, 1.0, 11.0, 20.0, 30.0, 1.0, 0.0])
	_check(not book.check_arrival("B", 2, b_records)["known"], "first visit not mislabelled verified")
	_check(book.note_saved("A", 1, a_records), "remember successful departure save")
	book.note_transition("A", "B")
	_check(book.return_id == "A" and book.transitions == 1, "return selection after A to B")
	_check(book.note_saved("B", 2, b_records), "independent destination save")
	book.note_transition("B", "A")
	_check(book.return_id == "B" and book.transitions == 2, "return selection after B to A")
	var audit: Dictionary = book.check_arrival("A", 1, a_records)
	_check(audit["known"] and audit["match"], "A saved records survive return")
	_check(book.check_arrival("B", 2, b_records)["match"], "B expectation not replaced by A")
	var changed: PackedFloat64Array = a_records.duplicate()
	changed[0] += 0.125
	_check(not book.check_arrival("A", 1, changed)["match"], "same revision but changed geometry refused")
	_check(not book.check_arrival("A", 2, a_records)["match"], "changed revision refused")
	_check(book.check_arrival("A", 1, a_records)["match"], "failed audit does not overwrite expectation")
	_check(not book.note_saved("A", 2, a_records), "invalid record count not stored")
	_check(book.check_arrival("A", 1, a_records)["match"], "invalid save leaves expectation intact")
	var empty: PackedFloat64Array = PackedFloat64Array()
	_check(book.note_saved("MOON", 0, empty) and book.check_arrival("MOON", 0, empty)["match"], "new moon empty journal")
	book.note_transition("A", "MOON")
	_check(book.return_id == "A" and book.transitions == 3, "moon follows same route logic")
	book.note_transition("MOON", "MOON")
	_check(book.transitions == 3, "same-body event not counted")
	var before: String = Book3.records_digest(a_records)
	book.check_arrival("A", 1, a_records)
	_check(Book3.records_digest(a_records) == before, "source records unchanged")
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_transfer_roundtrip_v3.gd")
	_check(source.contains("super._handover()") and source.contains("super._save_journal()"), "validated handover and save path retained")
	_check(not source.contains("func _tick_flight(") and not source.contains("func _flight_spheres(") and not source.contains("func _try_flight_landing(") and not source.contains("func _update_navigation_tick("), "collision/landing/navigation chain unchanged")
	_check(source.contains("KEY_1, KEY_2") and source.contains("LEGACY_SWITCH_BLOCKED"), "legacy switch blocked")
	_check(not source.contains("KEY_F8") and not source.contains("KEY_F6") and not source.contains("KEY_F7") and not source.contains("KEY_F9"), "no new function-key shortcuts")
	_check(source.contains("if _route_audit_blocked:"), "save guard on audit failure")
	_check(ResourceLoader.load("res://scenes/world/test_catalog_transfer_roundtrip_v3.tscn") is PackedScene, "scene resource parses")
	var instance = Scene3.new()
	instance.free()
	if _failures == 0:
		print("Transfer3: PASS per-body record digest/revision, A-B-A bookkeeping, moon/empty journal, mismatch retention, inherited handover, scene parse")
	print("Transfer3: tests do not prove real disk reload, landing, visible edit restoration or moon lighting; perform actual roundtrip")
	quit(0 if _failures == 0 else 1)
