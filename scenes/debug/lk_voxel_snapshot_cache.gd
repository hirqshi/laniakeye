extends RefCounted

const CACHE_DIRECTORY: String = "user://voxel_snapshot_cache_v1"
const BLOCK_SIZE: int = 16

var _database: VoxelStreamSQLite
var _mutex: Mutex = Mutex.new()

var _hits: int = 0
var _misses: int = 0
var _errors: int = 0
var _unsupported: int = 0
var _unsupported_examples: Dictionary = {}

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

	_mutex.lock()

	var result: int = _database.load_voxel_block(
		buffer,
		position,
		lod
	)

	if result == VoxelStream.RESULT_BLOCK_FOUND:
		_hits += 1
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

	# Never hand the terrain's mutable buffer to persistent storage.
	var snapshot: VoxelBuffer = VoxelBuffer.new()
	var size: Vector3i = buffer.get_size()

	snapshot.create(size.x, size.y, size.z)
	snapshot.set_channel_depth(
		VoxelBuffer.CHANNEL_SDF,
		buffer.get_channel_depth(VoxelBuffer.CHANNEL_SDF)
	)
	snapshot.copy_channel_from(buffer, VoxelBuffer.CHANNEL_SDF)

	var position: Vector3i = _block_position(origin, lod)

	_mutex.lock()
	_database.save_voxel_block(snapshot, position, lod)
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
	}

	_mutex.unlock()
	return result
