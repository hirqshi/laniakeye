extends RefCounted

const CACHE_DIRECTORY: String = "user://voxel_snapshot_cache_v1"
const BLOCK_SIZE: int = 16
const RAM_BLOCK_LIMIT: int = 4096

var _database: VoxelStreamSQLite
var _mutex: Mutex = Mutex.new()

var _hits: int = 0
var _misses: int = 0
var _errors: int = 0
var _unsupported: int = 0
var _unsupported_examples: Dictionary = {}

var _ram_blocks: Dictionary = {}
var _ram_order: Array[Vector4i] = []
var _ram_replace_index: int = 0

var _ram_hits: int = 0
var _sqlite_hits: int = 0
var _sqlite_reads: int = 0
var _ram_evictions: int = 0

var database_path: String = ""


# Configure once on the main thread, before publishing the generator.
func configure(identity: PackedByteArray) -> bool:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CACHE_DIRECTORY)
	)

	if directory_error != OK:
		push_warning(
			"VoxelSnapshotCache: cannot create directory; error=%d"
			% directory_error
		)
		return false

	var hasher: HashingContext = HashingContext.new()

	if hasher.start(HashingContext.HASH_SHA256) != OK:
		return false

	hasher.update(identity)

	var digest: String = hasher.finish().hex_encode()
	database_path = CACHE_DIRECTORY.path_join(digest + ".sqlite")

	_database = VoxelStreamSQLite.new()
	_database.database_path = database_path

	# This cache stores generated blocks, not only sparse player edits.
	# The optional key cache is intentionally not enabled.
	return true


func supports(
	buffer: VoxelBuffer,
	origin: Vector3i,
	lod: int
) -> bool:
	if _database == null:
		_record_unsupported("NO DATABASE", buffer, origin, lod)
		return false

	if lod < 0 or lod > 20:
		_record_unsupported("LOD RANGE", buffer, origin, lod)
		return false

	if buffer.get_size() != Vector3i(
		BLOCK_SIZE,
		BLOCK_SIZE,
		BLOCK_SIZE
	):
		_record_unsupported("BUFFER SIZE", buffer, origin, lod)
		return false

	var span: int = BLOCK_SIZE * (1 << lod)

	if (
		origin.x % span != 0
		or origin.y % span != 0
		or origin.z % span != 0
	):
		_record_unsupported("ORIGIN ALIGNMENT", buffer, origin, lod)
		return false

	return true


func _block_position(origin: Vector3i, lod: int) -> Vector3i:
	# supports() guarantees alignment, including negative origins.
	var shift: int = 4 + lod

	return Vector3i(
		origin.x >> shift,
		origin.y >> shift,
		origin.z >> shift
	)


func load_block(
	buffer: VoxelBuffer,
	origin: Vector3i,
	lod: int
) -> bool:
	if not supports(buffer, origin, lod):
		return false

	var position: Vector3i = _block_position(origin, lod)
	var key: Vector4i = _ram_key(position, lod)

	_mutex.lock()

	if _ram_blocks.has(key):
		var cached: VoxelBuffer = _ram_blocks[key]

		_copy_sdf(cached, buffer)

		_ram_hits += 1
		_hits += 1

		_mutex.unlock()
		return true

	_sqlite_reads += 1

	var result: int = _database.load_voxel_block(
		buffer,
		position,
		lod
	)

	if result == VoxelStream.RESULT_BLOCK_FOUND:
		_sqlite_hits += 1
		_hits += 1

		_remember_locked(
			key,
			_make_snapshot(buffer)
		)

	elif result == VoxelStream.RESULT_BLOCK_NOT_FOUND:
		_misses += 1
	else:
		_errors += 1

	_mutex.unlock()

	return result == VoxelStream.RESULT_BLOCK_FOUND


func store_block(
	buffer: VoxelBuffer,
	origin: Vector3i,
	lod: int
) -> void:
	if not supports(buffer, origin, lod):
		return

	var snapshot: VoxelBuffer = _make_snapshot(buffer)
	var position: Vector3i = _block_position(origin, lod)
	var key: Vector4i = _ram_key(position, lod)

	_mutex.lock()

	# Another worker may have generated or loaded this tile
	# while this worker was computing it.
	if _ram_blocks.has(key):
		_mutex.unlock()
		return

	_database.save_voxel_block(
		snapshot,
		position,
		lod
	)

	_remember_locked(key, snapshot)

	_mutex.unlock()


func _record_unsupported(
	reason: String,
	buffer: VoxelBuffer,
	origin: Vector3i,
	lod: int
) -> void:
	var size: Vector3i = buffer.get_size()
	var example_key: String = "%s|%s|%d" % [
		reason,
		str(size),
		lod,
	]

	_mutex.lock()

	_unsupported += 1

	if (
		not _unsupported_examples.has(example_key)
		and _unsupported_examples.size() < 12
	):
		_unsupported_examples[example_key] = (
			"reason=%s size=%s origin=%s lod=%d"
			% [
				reason,
				str(size),
				str(origin),
				lod,
			]
		)

	_mutex.unlock()


func try_get_stats() -> Dictionary:
	if not _mutex.try_lock():
		return {}

	var result: Dictionary = {
		"hits": _hits,
		"misses": _misses,
		"errors": _errors,
		"unsupported": _unsupported,
		"unsupported_examples": _unsupported_examples.values(),
		"ram_hits": _ram_hits,
		"sqlite_hits": _sqlite_hits,
		"sqlite_reads": _sqlite_reads,
		"ram_blocks": _ram_blocks.size(),
		"ram_evictions": _ram_evictions,
	}

	_mutex.unlock()
	return result


func _ram_key(position: Vector3i, lod: int) -> Vector4i:
	return Vector4i(
		position.x,
		position.y,
		position.z,
		lod
	)


func _copy_sdf(source: VoxelBuffer, destination: VoxelBuffer) -> void:
	destination.set_channel_depth(
		VoxelBuffer.CHANNEL_SDF,
		source.get_channel_depth(VoxelBuffer.CHANNEL_SDF)
	)
	destination.copy_channel_from(
		source,
		VoxelBuffer.CHANNEL_SDF
	)


func _make_snapshot(source: VoxelBuffer) -> VoxelBuffer:
	var snapshot: VoxelBuffer = VoxelBuffer.new()
	var size: Vector3i = source.get_size()

	snapshot.create(size.x, size.y, size.z)
	_copy_sdf(source, snapshot)

	return snapshot


# The caller must hold _mutex.
# Stored buffers remain private and immutable.
func _remember_locked(
	key: Vector4i,
	snapshot: VoxelBuffer
) -> void:
	if _ram_blocks.has(key):
		return

	if _ram_order.size() < RAM_BLOCK_LIMIT:
		_ram_order.append(key)
	else:
		var oldest: Vector4i = _ram_order[_ram_replace_index]
		_ram_blocks.erase(oldest)
		_ram_order[_ram_replace_index] = key
		_ram_replace_index = (
			(_ram_replace_index + 1) % RAM_BLOCK_LIMIT
		)
		_ram_evictions += 1

	_ram_blocks[key] = snapshot
