extends "res://scenes/debug/test_voxel_reanchor.gd"

const STREAM_DATABASE_PATH: String = (
	"user://voxel_stream_test.sqlite"
)

const STAMP_RADIUS_M: float = 1.5
const STAMP_REACH_M: float = 14.0
const MIN_STAMP_DISTANCE_M: float = 6.0

const AUTOSAVE_INTERVAL_S: float = 10.0

var _request_stamp: bool = false
var _request_build: bool = false
var _autosave_s: float = 0.0


func _ready() -> void:
	_stream = VoxelStreamSQLite.new()
	_stream.database_path = STREAM_DATABASE_PATH
	_stream.set_key_cache_enabled(true)

	super._ready()

	print(
		"VoxelStreamTest: database=%s"
		% STREAM_DATABASE_PATH
	)
	print(
		"VoxelStreamTest: LMB dig stamp, RMB build stamp. "
		+ "Aim 6-14 m away. Stream saves modified blocks."
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event

		if (
			button.pressed
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			and (
				button.button_index == MOUSE_BUTTON_LEFT
				or button.button_index == MOUSE_BUTTON_RIGHT
			)
		):
			if _request_stamp or _waiting or _failed:
				print("VoxelStreamTest: BUSY; click ignored")
				return

			_request_stamp = true
			_request_build = (
				button.button_index == MOUSE_BUTTON_RIGHT
			)
			return

	super._unhandled_input(event)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if _waiting or _failed:
		return

	_autosave_s += delta

	if _autosave_s >= AUTOSAVE_INTERVAL_S:
		_autosave_s = 0.0
		_save_stream("autosave")

	if _request_stamp:
		_request_stamp = false
		_accept_stamp(_request_build)


func _accept_stamp(build: bool) -> void:
	var camera: Camera3D = _player.player_camera
	var from: Vector3 = camera.global_position
	var forward: Vector3 = (
		-camera.global_basis.z.normalized()
	)

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
		print("VoxelStreamTest: NO HIT")
		return

	var point: Vector3 = hit["position"]

	if point.distance_to(_player.global_position) < MIN_STAMP_DISTANCE_M:
		print(
			"VoxelStreamTest: TOO CLOSE; aim at least "
			+ "%.1f m away" % MIN_STAMP_DISTANCE_M
		)
		return

	var relative: LkPosition64 = _rotation.relative_position(
		_frame.get_origin(),
		point
	)
	var center: LkPosition64 = _rotation.rotate(
		relative,
		-_rotation.angle_rad
	)

	if not _apply_stamp(center, STAMP_RADIUS_M, build):
		_fail_gate("stamp area is not editable")
		return

	print(
		"VoxelStreamTest: %s center=(%.3f, %.3f, %.3f) radius=%.3f"
		% [
			"BUILD" if build else "DIG",
			center.x,
			center.y,
			center.z,
			STAMP_RADIUS_M,
		]
	)

	_save_stream("after stamp")


func _apply_stamp(
	center: LkPosition64,
	radius: float,
	build: bool
) -> bool:
	var local_center: Vector3 = Vector3(
		center.x - float(_anchor.x),
		center.y - float(_anchor.y),
		center.z - float(_anchor.z)
	)

	# Match the conservative sphere reach used by the edited generator:
	# four voxels beyond the nominal radius at LOD 0.
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


func _save_stream(reason: String) -> void:
	if not is_instance_valid(_terrain):
		return

	var tracker: VoxelSaveCompletionTracker = (
		_terrain.save_modified_blocks()
	)

	print(
		"VoxelStreamTest: SAVE REQUESTED reason=%s"
		% reason
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_stream("window close")


func _process(delta: float) -> void:
	super._process(delta)

	_label.text += (
		"\n\nVOXEL STREAM TEST"
		+ "\nDatabase: %s"
		+ "\nLMB DIG / RMB BUILD | aim 6-14 m away"
		+ "\nAutosave every %.0f s"
	) % [
		STREAM_DATABASE_PATH,
		AUTOSAVE_INTERVAL_S,
	]
