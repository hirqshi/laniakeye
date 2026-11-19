extends "res://scenes/world/test_catalog_far_mesh.gd"

const NearbyQuery = preload("res://world/runtime/lk_nearby_stars.gd")
const SpatialStars = preload("res://world/runtime/lk_universe_spatial.gd")
const SpriteData = preload("res://world/rendering/lk_star_sprite_data.gd")
const StarSpriteBatch = preload("res://world/rendering/lk_star_sprites.gd")

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


func _ready() -> void:
	# Prepare BEFORE creating gameplay. Heavy cold sectors run on a loading screen,
	# not while the player walks. One-time data remains on this root across 1/2.
	set_physics_process(false)
	_star_loading_canvas = CanvasLayer.new()
	_star_loading_label = Label.new()
	_star_loading_label.position = Vector2(24.0, 24.0)
	_star_loading_canvas.add_child(_star_loading_label)
	add_child(_star_loading_canvas)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var definition = Definition.new()
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
		return
	_star_prepare_start_usec = Time.get_ticks_usec()


func _finish_star_preparation() -> void:
	_star_search_report = _star_query.result()
	if not _star_search_report["ok"] or not _star_search_report["complete"]:
		_star_loading_label.text = "Star search incomplete: " + str(_star_search_report)
		_abort_start("stars: incomplete spatial preparation")
		return
	_star_ready_data = SpriteData.build(_star_search_report["stars"], star_magnitude_limit, 8192)
	if not _star_ready_data["ok"] or not _star_ready_data["complete"]:
		_star_loading_label.text = "Star sprite preparation failed/incomplete"
		_abort_start("stars: sprite preparation failed/incomplete")
		return
	print("StarSprites: PREPARED candidates=%d magnitude_pass=%d sprites=%d cold_seconds=%.2f" % [
		_star_ready_data["input_candidates"], _star_ready_data["passed_magnitude"],
		_star_ready_data["stars"].size(), float(Time.get_ticks_usec() - _star_prepare_start_usec) / 1000000.0,
	])
	# Keep only the compact GPU-ready stars + summary; release heavy sector cache.
	_star_search_report.erase("stars")
	_star_query = null
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
	_star_sprite_node = StarSpriteBatch.new()
	_star_sprite_node.name = "ProceduralStarSprites"
	_star_sprite_node.configure(_star_ready_data["stars"], _player.player_camera, _catalog_far_node)
	_star_sprite_node.exposure_gain = star_exposure_gain
	add_child(_star_sprite_node)
	print("StarSprites: ATTACH body=%s sprites=%d same_system_data_reused=true" % [_context["body"]["id"], _star_ready_data["stars"].size()])


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
		_star_loading_label.text = ("Preparing catalog starfield (no gameplay yet)"
			+ "\nSectors %d / %d | candidates %d"
			+ "\nCold placement may take time; no invented background stars") % [
			progress["scanned_sectors"], progress["planned_sectors"], progress["matched_stars"],
		]
		if progress["finished"]:
			_finish_star_preparation()
		return
	super._process(delta)
	if _initialised and not _star_ready_data.is_empty():
		if is_instance_valid(_star_sprite_node):
			_star_sprite_node.exposure_gain = star_exposure_gain
		_label.text += "\nSTAR SPRITES candidates=%d passed=%d | %.0f ly | mag<=%.1f" % [
			_star_ready_data["input_candidates"], _star_ready_data["passed_magnitude"], _star_search_report["query_radius_ly"], _star_ready_data["magnitude_limit"],
		]


func _unhandled_input(event: InputEvent) -> void:
	if _star_loading:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_tree().quit()
		return
	super._unhandled_input(event)
