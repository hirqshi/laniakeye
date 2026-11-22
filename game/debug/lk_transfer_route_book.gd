extends RefCounted

var return_id: String = ""
var transitions: int = 0
var _saved: Dictionary = {}

static func records_digest(records: PackedFloat64Array) -> String:
	var hash_context: HashingContext = HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hash_context.update(var_to_bytes(records)) != OK:
		return ""
	return hash_context.finish().hex_encode()

func note_saved(id: String, revision: int, records: PackedFloat64Array) -> bool:
	if id.is_empty() or revision < 0 or records.size() != revision * 5:
		return false
	var digest: String = records_digest(records)
	if digest.is_empty():
		return false
	_saved[id] = {"revision": revision, "digest": digest}
	return true

# No baseline is silently overwritten on arrival or mismatch.
func check_arrival(id: String, revision: int, records: PackedFloat64Array) -> Dictionary:
	if not _saved.has(id):
		return {"known": false, "match": false}
	var expected: Dictionary = _saved[id]
	var digest: String = records_digest(records)
	return {"known": true, "match": revision == expected["revision"] and not digest.is_empty() and digest == expected["digest"],
		"expected_revision": expected["revision"], "actual_revision": revision}

func note_transition(from_id: String, to_id: String) -> void:
	if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		return
	return_id = from_id
	transitions += 1
