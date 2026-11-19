extends "res://scenes/world/test_catalog_far_mesh.gd"

const NearbyQuery = preload("res://world/runtime/lk_nearby_stars.gd")
const SpatialStars = preload("res://world/runtime/lk_universe_spatial.gd")
const SpriteData = preload("res://world/rendering/lk_star_sprite_data.gd")
const StarSpriteBatch = preload("res://world/rendering/lk_star_sprites.gd")
const StarDiskCache = preload("res://world/runtime/lk_star_candidate_cache.gd")

@export_range(1.0, 128.0, 1.0) var star_search_radius_ly: float = 128.0
@export var star_magnitude_limit: float = 6.0
@export_range(1, 16, 1) var star_prepare_sectors_per_frame: int = 4
@export var star_exposure_gain: float = 0.8

var _star_query
var _star_loading: bool = true
var _star_loading_canvas: CanvasLayer
var _star_loading_label: Label
var _star_ready_data: Dictionary = {}
var _star_search_report: Dictionary = {}
var _star_sprite_node: StarSpriteBatch
var _star_prepare_start_usec: int = 0
var _star_disk_key: Dictionary = {}
var _star_disk_path: String = ""
var _star_cache_mode: String = "COLD"

func _ready() -> void:
	set_physics_process(false)
	_star_loading_canvas = CanvasLayer.new()
	_star_loading_label = Label.new()
	_star_loading_label.position = Vector2(24.0, 24.0)
	_star_loading_label.text = "Checking star candidate cache..."
	_star_loading_canvas.add_child(_star_loading_label)
	add_child(_star_loading_canvas)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var definition = Definition.new()
	var key_started: int = Time.get_ticks_usec()
	_star_disk_key = StarDiskCache.manifest(definition, [galaxy_index, sector_x, sector_y, sector_z, system_slot], star_search_radius_ly)
	_star_disk_path = StarDiskCache.cache_path(_star_disk_key)
	var read_started: int = Time.get_ticks_usec()
	var loaded: Dictionary = StarDiskCache.load_cache(_star_disk_path, _star_disk_key)
	if loaded["ok"]:
		_star_cache_mode = "DISK HIT"
		print("StarCache: HIT candidates=%d fingerprint_ms=%.2f read_validate_ms=%.2f neighbor_sector_builds=0" % [loaded["payload"]["stars"].size(), float(read_started - key_started) / 1000.0, float(Time.get_ticks_usec() - read_started) / 1000.0])
		_accept_star_candidates(loaded["payload"])
		return
	print("StarCache: MISS reason=%s path=%s" % [loaded["reason"], _star_disk_path])
	_star_prepare_start_usec = Time.get_ticks_usec()
	var observer: Dictionary = SpatialStars.resolve_system(definition, galaxy_index, sector_x, sector_y, sector_z, system_slot)
	if not observer["ok"]:
		_star_loading_label.text = "Star preparation failed: " + str(observer["code"])
		_abort_start("stars: " + str(observer["code"]))
		return
	_star_query = NearbyQuery.new(definition, 4096)
	var started: Dictionary = _star_query.begin(observer["location"], star_search_radius_ly, [0.0, 0.0, 0.0], 8192, 32768)
	if not started["ok"]:
		_star_loading_label.text = "Star query failed: " + str(started["code"])
		_abort_start("stars: " + str(started["code"]))

func _finish_star_preparation() -> void:
	var report: Dictionary = _star_query.result()
	if not report["ok"] or not report["complete"]:
		_star_loading_label.text = "Star search failed/incomplete"
		_abort_start("stars: incomplete spatial preparation")
		return
	var payload: Dictionary = StarDiskCache.compact(report)
	print("StarCache: COLD candidates=%d search_seconds=%.2f" % [payload["stars"].size(), float(Time.get_ticks_usec() - _star_prepare_start_usec) / 1000000.0])
	var save_started: int = Time.get_ticks_usec()
	if StarDiskCache.save_cache(_star_disk_path, _star_disk_key, payload):
		print("StarCache: SAVED candidates=%d save_ms=%.2f path=%s" % [payload["stars"].size(), float(Time.get_ticks_usec() - save_started) / 1000.0, _star_disk_path])
	else:
		push_warning("StarCache: SAVE FAILED; proceeding without persistent cache")
	_accept_star_candidates(payload)

func _accept_star_candidates(payload: Dictionary) -> void:
	var photo_started: int = Time.get_ticks_usec()
	_star_ready_data = SpriteData.build(payload["stars"], star_magnitude_limit, 8192)
	if not _star_ready_data["ok"] or not _star_ready_data["complete"]:
		_star_loading_label.text = "Star sprite preparation failed/incomplete"
		_abort_start("stars: sprite preparation failed/incomplete")
		return
	_star_search_report = payload["report"].duplicate(true)
	_star_query = null
	print("StarSprites: PREPARED candidates=%d sprites=%d photometry_ms=%.2f source=%s" % [_star_ready_data["input_candidates"], _star_ready_data["stars"].size(), float(Time.get_ticks_usec() - photo_started) / 1000.0, _star_cache_mode])
	_start_star_world.call_deferred()

func _start_star_world() -> void:
	remove_child(_star_loading_canvas)
	_star_loading_canvas.queue_free()
	_star_loading_canvas = null
	_star_loading = false
	super._ready()
	if _initialised and not _failed:
		set_physics_process(true)

func _load_target(index: int) -> void:
	super._load_target(index)
	if _star_loading or not _initialised or _failed or is_instance_valid(_star_sprite_node):
		return
	var gpu_started: int = Time.get_ticks_usec()
	_star_sprite_node = StarSpriteBatch.new()
	_star_sprite_node.name = "ProceduralStarSprites"
	_star_sprite_node.configure(_star_ready_data["stars"], _player.player_camera, _catalog_far_node)
	_star_sprite_node.exposure_gain = star_exposure_gain
	add_child(_star_sprite_node)
	print("StarSprites: ATTACH body=%s sprites=%d batch_setup_ms=%.2f same_system_data_reused=true" % [_context["body"]["id"], _star_ready_data["stars"].size(), float(Time.get_ticks_usec() - gpu_started) / 1000.0])

func _close_local_world() -> void:
	if is_instance_valid(_star_sprite_node):
		remove_child(_star_sprite_node)
		_star_sprite_node.queue_free()
		_star_sprite_node = null
	super._close_local_world()

func _process(delta: float) -> void:
	if _star_loading:
		if _star_query == null or _failed:
			return
		var progress: Dictionary = _star_query.step(clampi(star_prepare_sectors_per_frame, 1, 16))
		if not progress["ok"]:
			_star_loading_label.text = "Star search failed: " + str(progress["code"])
			_abort_start("stars: " + str(progress["code"]))
			return
		_star_loading_label.text = "Preparing stars (first compatible load)\nSectors %d / %d | candidates %d\nComplete result will be cached on disk" % [progress["scanned_sectors"], progress["planned_sectors"], progress["matched_stars"]]
		if progress["finished"]:
			_finish_star_preparation()
		return
	super._process(delta)
	if _initialised and not _star_ready_data.is_empty():
		if is_instance_valid(_star_sprite_node):
			_star_sprite_node.exposure_gain = star_exposure_gain
		_label.text += "\nSTAR SPRITES candidates=%d passed=%d | %.0f ly | mag<=%.1f | %s" % [_star_ready_data["input_candidates"], _star_ready_data["passed_magnitude"], _star_search_report["query_radius_ly"], _star_ready_data["magnitude_limit"], _star_cache_mode]

func _unhandled_input(event: InputEvent) -> void:
	if _star_loading:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_tree().quit()
		return
	super._unhandled_input(event)
