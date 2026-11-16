extends "res://scenes/debug/test_voxel_reanchor_edits.gd"

const STAMP_RADIUS_M: float = 1.5
const STAMP_REACH_M: float = 14.0
const MIN_STAMP_DISTANCE_M: float = 6.0
const PUBLICATION_SDF_TOLERANCE: float = 0.0001
const PUBLICATION_COLLIDER_SDF_TOLERANCE: float = 0.1
const JOURNAL_SAVE_PATH: String = (
	"user://voxel_edit_publication_journal.json"
)
const JOURNAL_FORMAT_VERSION: int = 1

var _request_stamp: bool = false
var _request_build: bool = false

var _publishing: bool = false
var _publication_center: LkPosition64
var _publication_revision: int = 0
var _publication_samples_checked: bool = false


func _ready() -> void:
	super._ready()

	# This scene is an interactive publication test, not the automatic
	# single-edit return-and-compare gate inherited from Gate 2b.
	_edit_phase = "PASS"

	if _load_journal():
		print(
			"VoxelPublication: LOADED journal revision=%d operations=%d"
			% [
				_edit_journal.get_revision(),
				_edit_journal.get_count(),
			]
		)
	else:
		if not _save_journal():
			_fail_gate("failed to create initial journal save")
			return

		print(
			"VoxelPublication: STARTED journal revision=%d operations=%d"
			% [
				_edit_journal.get_revision(),
				_edit_journal.get_count(),
			]
		)

	print(
		"VoxelPublication: LMB dig stamp, RMB build stamp. "
		+ "Aim 6-14 m away. Local LOD 0 edits; journal records every click."
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event

		if (
			button.pressed
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			and button.button_index in [
				MOUSE_BUTTON_LEFT,
				MOUSE_BUTTON_RIGHT,
			]
		):
			if (
				_request_stamp
				or _publishing
				or is_instance_valid(_pending)
				or _waiting
				or _failed
			):
				print("VoxelPublication: BUSY; click ignored")
				return

			_request_stamp = true
			_request_build = button.button_index == MOUSE_BUTTON_RIGHT
			return

	super._unhandled_input(event)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if _waiting or _failed:
		return

	if _request_stamp:
		_request_stamp = false

		if (
			not _publishing
			and not is_instance_valid(_pending)
			and not _stream_hold
			and not _movement_paused
		):
			_accept_stamp(_request_build)
		else:
			print("VoxelPublication: BUSY at physics boundary; click ignored")


func _accept_stamp(build: bool) -> void:
	var camera: Camera3D = _player.player_camera
	var from: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_basis.z.normalized()

	var query: PhysicsRayQueryParameters3D = (
		PhysicsRayQueryParameters3D.create(
			from,
			from + forward * STAMP_REACH_M,
			ACTIVE_LAYER,
			[_player.get_rid()]
		)
	)

	var hit: Dictionary = (
		get_world_3d().direct_space_state.intersect_ray(query)
	)

	if hit.is_empty():
		print("VoxelPublication: NO HIT")
		return

	var point: Vector3 = hit["position"]

	if point.distance_to(_player.global_position) < MIN_STAMP_DISTANCE_M:
		print("VoxelPublication: TOO CLOSE; aim at least 6 m away")
		return

	var relative: LkPosition64 = _rotation.relative_position(
		_frame.get_origin(),
		point
	)
	_publication_center = _rotation.rotate(
		relative,
		-_rotation.angle_rad
	)

	if not _edit_journal.append_sphere(
		_publication_center,
		STAMP_RADIUS_M,
		build
	):
		_fail_gate("journal rejected stamp")
		return

	if not _apply_local_stamp(
		_publication_center,
		STAMP_RADIUS_M,
		build
	):
		_fail_gate("local stamp area is not editable")
		return

	if not _save_journal():
		_fail_gate("failed to save journal after local stamp")
		return

	print(
		"VoxelPublication: LOCAL %s revision=%d operations=%d"
		% [
			"DIG" if not build else "BUILD",
			_edit_journal.get_revision(),
			_edit_journal.get_count(),
		]
	)


func _choose_anchor(fixed: LkPosition64) -> LkPosition64:
	if _publishing:
		# Change the world version without also relocating the patch anchor.
		return _anchor.copy()

	return super._choose_anchor(fixed)


func _check_pending() -> bool:
	var generator: EditedGenerator = _pending.generator as EditedGenerator

	if generator == null:
		_build_reason = "INVALID GENERATOR"
		return false

	if generator.get_revision() != _edit_journal.get_revision():
		_build_reason = "STALE JOURNAL REVISION"
		return false

	return super._check_pending()


func _check_publication(generator: EditedGenerator) -> bool:
	var player_local: Vector3 = _pending.to_local(
		_player.global_position
	)
	var player_area: AABB = AABB(
		player_local - Vector3.ONE * 8.0,
		Vector3.ONE * 16.0
	)

	var center_local: Vector3 = Vector3(
		_publication_center.x - _pending_anchor.x,
		_publication_center.y - _pending_anchor.y,
		_publication_center.z - _pending_anchor.z
	)
	var edit_area: AABB = AABB(
		center_local - Vector3.ONE * 5.0,
		Vector3.ONE * 10.0
	)

	if (
		not _pending.is_area_meshed(player_area, 0)
		or not _pending.is_area_meshed(edit_area, 0)
	):
		_build_reason = "PUBLICATION WAITING FOR MESH"
		return false

	var tool: VoxelToolLodTerrain = _pending.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_SDF

	if not tool.is_area_editable(edit_area):
		_build_reason = "PUBLICATION WAITING FOR DATA"
		return false

	if not _publication_samples_checked:
		if not _check_publication_samples(generator, tool):
			_build_reason = "PUBLICATION SDF MISMATCH"
			return false

		_publication_samples_checked = true

	if not _check_publication_colliders(tool):
		_build_reason = "PUBLICATION EDIT COLLIDERS NOT READY"
		return false

	if not _publication_capsule_is_clear():
		_build_reason = "PUBLICATION PLAYER OVERLAPS NEW TERRAIN"
		return false

	# A jumping player does not need ground directly underneath.
	# A grounded player should have support in the replacement patch.
	if _player.is_on_floor():
		if not _publication_has_ground_support():
			_build_reason = "PUBLICATION PLAYER SUPPORT NOT READY"
			return false

	_build_reason = "PUBLICATION READY"

	# Old and new surfaces intentionally differ during publication.
	# Zero here is NOT a measured old/new profile error.
	_last_profile_error_m = 0.0
	return true


func _publication_has_ground_support() -> bool:
	var point: Vector3 = _player.global_position
	var up: Vector3 = _player.up_direction.normalized()
	var flat: Basis = _basis_for_up(up)

	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		flat.x * 0.15,
		-flat.x * 0.15,
		flat.z * 0.15,
		-flat.z * 0.15,
	]

	for offset: Vector3 in offsets:
		var hit: Dictionary = _ground_hit(
			point + offset,
			STAGING_LAYER
		)

		if hit.is_empty():
			continue

		var hit_point: Vector3 = hit["position"]
		var height: float = (point - hit_point).dot(up)

		if height >= 0.5 and height <= 1.4:
			return true

	return false


func _check_publication_samples(
	generator: EditedGenerator,
	tool: VoxelToolLodTerrain
) -> bool:
	var center_voxel: Vector3i = Vector3i(
		int(roundf(_publication_center.x - _pending_anchor.x)),
		int(roundf(_publication_center.y - _pending_anchor.y)),
		int(roundf(_publication_center.z - _pending_anchor.z))
	)

	var expected: VoxelBuffer = VoxelBuffer.new()
	expected.create(1, 1, 1)

	var worst: float = 0.0

	for x: int in [-2, 0, 2]:
		for y: int in [-2, 0, 2]:
			for z: int in [-2, 0, 2]:
				var voxel: Vector3i = center_voxel + Vector3i(x, y, z)

				generator._generate_block(expected, voxel, 0)

				var reference: float = expected.get_voxel_f(
					0, 0, 0, VoxelBuffer.CHANNEL_SDF
				)
				var actual: float = tool.get_voxel_f(voxel)
				worst = maxf(worst, absf(actual - reference))

	if worst > PUBLICATION_SDF_TOLERANCE:
		return false

	print(
		"VoxelPublication: SDF CHECK revision=%d samples=27 max_error=%.8f"
		% [_publication_revision, worst]
	)
	return true


func _planet_point_to_local(q: LkPosition64) -> Vector3:
	return _fixed_to_local(q)


func _check_publication_colliders(tool: VoxelToolLodTerrain) -> bool:
	var up: Vector3 = _publication_center.direction()
	var axes: Basis = _basis_for_up(up)

	for x: float in [-0.5, 0.0, 0.5]:
		for z: float in [-0.5, 0.0, 0.5]:
			var offset: Vector3 = (
				axes.x * (x + 0.00137)
				+ axes.z * (z + 0.00219)
			)
			var q: LkPosition64 = _publication_center.plus_local(offset)

			var top: Vector3 = _planet_point_to_local(
				q.plus_local(up * 8.0)
			)
			var bottom: Vector3 = _planet_point_to_local(
				q.plus_local(-up * 8.0)
			)

			var query: PhysicsRayQueryParameters3D = (
				PhysicsRayQueryParameters3D.create(
					top,
					bottom,
					STAGING_LAYER,
					[_player.get_rid()]
				)
			)

			var hit: Dictionary = (
				get_world_3d().direct_space_state.intersect_ray(query)
			)

			if hit.is_empty():
				return false

			var point: Vector3 = hit["position"]
			var local: Vector3 = _pending.to_local(point)
			var sdf: float = tool.get_voxel_f_interpolated(local)

			if (
				not is_finite(sdf)
				or absf(sdf) > PUBLICATION_COLLIDER_SDF_TOLERANCE
			):
				return false

	return true


func _commit_patch() -> void:
	var generator: EditedGenerator = _pending.generator as EditedGenerator

	if (
		generator == null
		or generator.get_revision() != _edit_journal.get_revision()
	):
		_fail_gate("refusing stale patch at commit")
		return
		
	if _publishing and not _publication_capsule_is_clear():
		_pending_stable_ticks = 0
		_build_reason = "PUBLICATION PLAYER OVERLAPS NEW TERRAIN"
		return
		
	var was_publication: bool = _publishing
	super._commit_patch()

	if was_publication:
		_publishing = false

		print(
			"VoxelPublication: PUBLISHED revision=%d operations=%d"
			% [
				generator.get_revision(),
				_edit_journal.get_count(),
			]
		)


func _apply_local_stamp(
	center: LkPosition64,
	radius: float,
	build: bool
) -> bool:
	var local_center: Vector3 = Vector3(
		center.x - float(_anchor.x),
		center.y - float(_anchor.y),
		center.z - float(_anchor.z)
	)

	# Match the generator's conservative sphere reach at LOD 0.
	var reach: float = radius + 4.0

	var min_corner: Vector3i = Vector3i(
		int(floor(local_center.x - reach)),
		int(floor(local_center.y - reach)),
		int(floor(local_center.z - reach))
	)
	var max_corner: Vector3i = Vector3i(
		int(ceil(local_center.x + reach)),
		int(ceil(local_center.y + reach)),
		int(ceil(local_center.z + reach))
	)

	var area: AABB = AABB(
		Vector3(min_corner),
		Vector3(max_corner - min_corner + Vector3i.ONE)
	)

	var tool: VoxelToolLodTerrain = _terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_SDF

	if not tool.is_area_editable(area):
		return false

	for x: int in range(min_corner.x, max_corner.x + 1):
		for y: int in range(min_corner.y, max_corner.y + 1):
			for z: int in range(min_corner.z, max_corner.z + 1):
				var position: Vector3 = Vector3(x, y, z)
				var distance: float = (
					position.distance_to(local_center)
				)
				var sphere_sdf: float = distance - radius
				var current: float = tool.get_voxel_f(position)

				var result: float
				if build:
					result = minf(current, sphere_sdf)
				else:
					result = maxf(current, -sphere_sdf)

				tool.set_voxel_f(
					position,
					clampf(result, -4.0, 4.0)
				)

	return true


func _publication_capsule_is_clear() -> bool:
	# Use a slightly smaller capsule so ordinary floor contact does not
	# count as the player being embedded in the replacement terrain.
	var probe: CapsuleShape3D = CapsuleShape3D.new()
	probe.radius = maxf(_capsule.radius - 0.02, 0.01)
	probe.height = maxf(
		_capsule.height - 0.04,
		probe.radius * 2.0
	)

	var query: PhysicsShapeQueryParameters3D = (
		PhysicsShapeQueryParameters3D.new()
	)
	query.shape = probe
	query.transform = _player.global_transform
	query.collision_mask = STAGING_LAYER
	query.exclude = [_player.get_rid()]
	query.margin = 0.0
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var overlaps: Array[Dictionary] = (
		get_world_3d().direct_space_state.intersect_shape(query, 1)
	)

	return overlaps.is_empty()


func _process(delta: float) -> void:
	super._process(delta)

	var active_revision: int = -1
	var active: EditedGenerator = _terrain.generator as EditedGenerator

	if active != null:
		active_revision = active.get_revision()

	_label.text += (
		"\n\nSTAMP PUBLICATION"
		+ "\nJournal revision: %d | active revision: %d"
		+ "\nOperations: %d | publishing: %s"
		+ "\nLMB DIG / RMB BUILD | aim 6-14 m away"
		+ "\nInstant local stamp; journal records every click"
	) % [
		_edit_journal.get_revision(),
		active_revision,
		_edit_journal.get_count(),
		_publishing,
	]


func _save_journal() -> bool:
	var records: PackedFloat64Array = _edit_journal.copy_records()

	if records.size() % 5 != 0:
		push_error(
			"VoxelPublication: journal record size is not a multiple of 5"
		)
		return false

	var operations: Array = []

	for index: int in range(0, records.size(), 5):
		operations.append([
			records[index],
			records[index + 1],
			records[index + 2],
			records[index + 3],
			records[index + 4] > 0.5,
		])

	var document: Dictionary = {
		"version": JOURNAL_FORMAT_VERSION,
		"revision": _edit_journal.get_revision(),
		"operations": operations,
	}

	var file: FileAccess = FileAccess.open(
		JOURNAL_SAVE_PATH,
		FileAccess.WRITE
	)

	if file == null:
		push_warning(
			"VoxelPublication: cannot open journal save file: %s"
			% JOURNAL_SAVE_PATH
		)
		return false

	file.store_string(JSON.stringify(document))
	file.close()
	return true


func _load_journal() -> bool:
	if not FileAccess.file_exists(JOURNAL_SAVE_PATH):
		return false

	var file: FileAccess = FileAccess.open(
		JOURNAL_SAVE_PATH,
		FileAccess.READ
	)

	if file == null:
		push_warning(
			"VoxelPublication: cannot open journal save file: %s"
			% JOURNAL_SAVE_PATH
		)
		return false

	var text: String = file.get_as_text()
	file.close()

	var document: Variant = JSON.parse_string(text)

	if typeof(document) != TYPE_DICTIONARY:
		push_warning("VoxelPublication: journal save file is not valid JSON")
		return false

	var saved_version: int = int(document.get("version", -1))
	var saved_revision: int = int(document.get("revision", -1))
	var entries: Variant = document.get("operations", null)

	if saved_version != JOURNAL_FORMAT_VERSION:
		push_warning(
			"VoxelPublication: unsupported journal format version %d"
			% saved_version
		)
		return false

	if typeof(entries) != TYPE_ARRAY:
		push_warning("VoxelPublication: journal operations are missing")
		return false

	if saved_revision != entries.size():
		push_warning(
			"VoxelPublication: journal revision does not match operation count"
		)
		return false

	var journal: LkVoxelEditJournal = LkVoxelEditJournal.new()

	for entry: Variant in entries:
		if typeof(entry) != TYPE_ARRAY or entry.size() != 5:
			push_warning(
				"VoxelPublication: invalid journal operation entry"
			)
			return false

		var center: LkPosition64 = LkPosition64.new(
			float(entry[0]),
			float(entry[1]),
			float(entry[2])
		)

		if not journal.append_sphere(
			center,
			float(entry[3]),
			bool(entry[4])
		):
			push_warning(
				"VoxelPublication: journal rejected a saved operation"
			)
			return false

	_edit_journal = journal
	_terrain.generator = _make_patch_generator(_anchor)

	return true
