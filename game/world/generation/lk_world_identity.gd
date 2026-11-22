class_name LkWorldIdentity
extends RefCounted

const ID_SCHEMA: String = "lk-world-id-v1"
const SEED_SCHEMA: String = "lk-world-seed-v1"


static func is_valid_id(value: String) -> bool:
	if value.length() != 32:
		return false
	for i: int in range(value.length()):
		if "0123456789abcdef".find(value.substr(i, 1)) < 0:
			return false
	return true


static func _digest(parts: PackedStringArray) -> PackedByteArray:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		push_error("LkWorldIdentity: SHA-256 initialization failed")
		return PackedByteArray()

	for part: String in parts:
		var bytes: PackedByteArray = part.to_utf8_buffer()
		var count: int = bytes.size()
		if count > 0xffffffff:
			push_error("LkWorldIdentity: input field is too large")
			return PackedByteArray()
		var prefix: PackedByteArray = PackedByteArray([
			(count >> 24) & 255,
			(count >> 16) & 255,
			(count >> 8) & 255,
			count & 255,
		])
		if context.update(prefix) != OK:
			return PackedByteArray()
		if not bytes.is_empty():
			if context.update(bytes) != OK:
				return PackedByteArray()

	return context.finish()


static func universe_id(seed_text: String) -> String:
	var bytes: PackedByteArray = _digest(PackedStringArray([
		ID_SCHEMA, "universe", seed_text,
	]))
	if bytes.size() != 32:
		return ""
	return bytes.slice(0, 16).hex_encode()


static func child_id(parent: String, domain: String, key: String) -> String:
	if not is_valid_id(parent) or domain.is_empty():
		push_error("LkWorldIdentity: invalid parent ID or empty domain")
		return ""
	var bytes: PackedByteArray = _digest(PackedStringArray([
		ID_SCHEMA, "child", parent, domain, key,
	]))
	if bytes.size() != 32:
		return ""
	return bytes.slice(0, 16).hex_encode()


static func seed63(object_id: String, domain: String, version: int) -> int:
	if not is_valid_id(object_id) or domain.is_empty() or version < 1:
		push_error("LkWorldIdentity: invalid seed request")
		return -1
	var bytes: PackedByteArray = _digest(PackedStringArray([
		SEED_SCHEMA, object_id, domain, str(version),
	]))
	if bytes.size() != 32:
		return -1
	var result: int = int(bytes[0]) & 127
	for i: int in range(1, 8):
		result = (result << 8) | int(bytes[i])
	return result
