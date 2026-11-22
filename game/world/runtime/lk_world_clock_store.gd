class_name LkWorldClockStore
extends RefCounted

const Identity = preload("res://game/world/generation/lk_world_identity.gd")
const Clock = preload("res://game/world/runtime/lk_world_clock.gd")
const ROOT: String = "user://world_foundation_v1"


static func clock_path(universe_id: String) -> String:
	if not Identity.is_valid_id(universe_id):
		return ""
	return ROOT.path_join(universe_id).path_join("world_clock.bin")


static func _checksum(payload: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(payload)
	return context.finish().hex_encode()


static func save_clock(universe_id: String, clock) -> bool:
	var path: String = clock_path(universe_id)
	var epoch: float = clock.now_s()
	if path.is_empty() or not is_finite(epoch) or epoch < 0.0 or epoch > Clock.MAX_EPOCH_S:
		return false
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK:
		return false
	var payload: PackedByteArray = var_to_bytes({"format": 1, "universe_id": universe_id, "epoch_s": epoch})
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_var({"format": 1, "sha256": _checksum(payload), "payload": payload}, false)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) == OK


static func load_clock(universe_id: String) -> Dictionary:
	var path: String = clock_path(universe_id)
	if path.is_empty():
		return {"ok": false, "error": "invalid universe ID"}
	var clock = Clock.new()
	if not FileAccess.file_exists(path):
		return {"ok": true, "found": false, "clock": clock}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot open clock file"}
	if file.get_length() > 4096:
		file.close()
		return {"ok": false, "error": "clock file too large"}
	var wrapper: Variant = file.get_var(false)
	file.close()
	if not wrapper is Dictionary or wrapper.get("format", -1) != 1:
		return {"ok": false, "error": "invalid clock wrapper"}
	var payload: Variant = wrapper.get("payload", null)
	if not payload is PackedByteArray or _checksum(payload) != wrapper.get("sha256", ""):
		return {"ok": false, "error": "clock checksum mismatch"}
	var document: Variant = bytes_to_var(payload)
	if not document is Dictionary or document.get("format", -1) != 1 or document.get("universe_id", "") != universe_id:
		return {"ok": false, "error": "clock identity/format mismatch"}
	var epoch: Variant = document.get("epoch_s", null)
	if typeof(epoch) != TYPE_FLOAT or not clock.restore(epoch):
		return {"ok": false, "error": "invalid saved epoch"}
	return {"ok": true, "found": true, "clock": clock}
