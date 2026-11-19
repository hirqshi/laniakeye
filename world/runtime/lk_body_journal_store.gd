class_name LkBodyJournalStore
extends RefCounted

const Identity = preload("res://world/generation/lk_world_identity.gd")
const ROOT: String = "user://world_foundation_v1"


static func journal_path(manifest: Dictionary) -> String:
	var universe: String = manifest.get("universe_id", "")
	var body: String = manifest.get("body_id", "")
	if not Identity.is_valid_id(universe) or not Identity.is_valid_id(body):
		return ""
	return ROOT.path_join(universe).path_join(body).path_join("journal.bin")


static func _digest(bytes: PackedByteArray) -> String:
	var hash_context: HashingContext = HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hash_context.update(bytes)
	return hash_context.finish().hex_encode()


static func write_journal(manifest: Dictionary, journal: LkVoxelEditJournal) -> bool:
	var path: String = journal_path(manifest)
	if path.is_empty():
		return false
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK:
		return false
	var payload: PackedByteArray = var_to_bytes({
		"manifest": manifest, "revision": journal.get_revision(), "records": journal.copy_records(),
	})
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_var({"format": 1, "sha256": _digest(payload), "payload": payload}, false)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)
	) == OK


static func read_journal(manifest: Dictionary) -> Dictionary:
	var path: String = journal_path(manifest)
	if path.is_empty():
		return {"ok": false, "error": "invalid journal address"}
	if not FileAccess.file_exists(path):
		return {"ok": true, "found": false, "journal": LkVoxelEditJournal.new()}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot open journal"}
	if file.get_length() > 64 * 1024 * 1024:
		file.close()
		return {"ok": false, "error": "journal exceeds development size limit"}
	var wrapper: Variant = file.get_var(false)
	file.close()
	if not wrapper is Dictionary or wrapper.get("format", -1) != 1:
		return {"ok": false, "error": "invalid journal wrapper"}
	var payload: Variant = wrapper.get("payload", null)
	if not payload is PackedByteArray or _digest(payload) != wrapper.get("sha256", ""):
		return {"ok": false, "error": "journal checksum mismatch"}
	var document: Variant = bytes_to_var(payload)
	if not document is Dictionary or document.get("manifest", {}) != manifest:
		return {"ok": false, "error": "journal manifest mismatch"}
	var records: Variant = document.get("records", null)
	if not records is PackedFloat64Array or records.size() % 5 != 0:
		return {"ok": false, "error": "invalid record array"}
	if int(document.get("revision", -1)) * 5 != records.size():
		return {"ok": false, "error": "invalid journal revision"}
	var journal: LkVoxelEditJournal = LkVoxelEditJournal.new()
	for index: int in range(0, records.size(), 5):
		for j: int in range(5):
			if not is_finite(records[index + j]):
				return {"ok": false, "error": "nonfinite record"}
		if records[index + 3] <= 0.0 or records[index + 4] not in [0.0, 1.0]:
			return {"ok": false, "error": "invalid brush parameters"}
		if not journal.append_sphere(LkPosition64.new(records[index], records[index + 1], records[index + 2]), records[index + 3], records[index + 4] > 0.5):
			return {"ok": false, "error": "journal rejected operation"}
	return {"ok": true, "found": true, "journal": journal}
