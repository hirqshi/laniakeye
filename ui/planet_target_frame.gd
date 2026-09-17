extends Control
class_name PlanetTargetFrame

## Рамка вокруг ближайшей к центру экрана планеты ИЛИ луны (только пока
## пилотируешь корабль). Источник целей - StarSystem.get_all_celestial_nodes(),
## которая собирает и планеты, и вложенные в них луны в один плоский список.
##
## Рамка - ОДНА atlas-текстура с 4 уголками, нарезаемая кодом через
## AtlasTexture.region на 4 TextureRect. Никаких 4 разных файлов - один
## corner_atlas назначается в инспекторе, region_rect для каждого угла
## считается автоматически в _ready() из corner_atlas_grid.
##
## Имя - временная заглушка до готовности генератора названий;
## landscape_type - реальный (surface_profile.profile_name через planet.gd).

@export var camera: Camera3D
@export var min_screen_radius_px: float = 24.0
@export var max_screen_radius_px: float = 220.0
@export var corner_inset_px: float = 12.0

## Один атлас с 4 уголками рамки, выложенными 2x2:
## [top-left, top-right]
## [bottom-left, bottom-right]
@export var corner_atlas: Texture2D:
	set(value):
		corner_atlas = value
		_slice_atlas()

@onready var _corner_top_left: TextureRect = $CornerTopLeft
@onready var _corner_top_right: TextureRect = $CornerTopRight
@onready var _corner_bottom_left: TextureRect = $CornerBottomLeft
@onready var _corner_bottom_right: TextureRect = $CornerBottomRight
@onready var _info_label: Label = $InfoLabel

var _is_piloting_ship: bool = false
var _star_system: Node3D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_slice_atlas()

	var hud: HudController = _find_hud_controller()
	if hud:
		hud.ui_color_changed.connect(_on_ui_color_changed)
		_on_ui_color_changed(hud.ui_color)

## Cuts corner_atlas (one 2x2 sprite sheet) into 4 AtlasTexture regions,
## one per corner TextureRect. Runs once when corner_atlas is assigned
## (editor or code) - not per-frame, slicing is static per texture.
func _slice_atlas() -> void:
	if corner_atlas == null:
		return
	if _corner_top_left == null:
		return

	var full_size: Vector2 = corner_atlas.get_size()
	var half_w: float = full_size.x * 0.5
	var half_h: float = full_size.y * 0.5

	_assign_region(_corner_top_left, Rect2(0.0, 0.0, half_w, half_h))
	_assign_region(_corner_top_right, Rect2(half_w, 0.0, half_w, half_h))
	_assign_region(_corner_bottom_left, Rect2(0.0, half_h, half_w, half_h))
	_assign_region(_corner_bottom_right, Rect2(half_w, half_h, half_w, half_h))

func _assign_region(corner: TextureRect, region: Rect2) -> void:
	if corner == null:
		return
	var atlas_tex: AtlasTexture = AtlasTexture.new()
	atlas_tex.atlas = corner_atlas
	atlas_tex.region = region
	corner.texture = atlas_tex

func set_camera(new_camera: Camera3D) -> void:
	camera = new_camera

func set_piloting_ship(value: bool) -> void:
	_is_piloting_ship = value

## Вызывается извне (World) один раз после спавна.
func setup(star_system: Node3D) -> void:
	_star_system = star_system

func _process(_delta: float) -> void:
	if not _is_piloting_ship or camera == null or _star_system == null:
		visible = false
		return

	var best: Dictionary = _find_best_target()
	if best.is_empty():
		visible = false
		return

	visible = true
	_update_frame(best)

func _find_best_target() -> Dictionary:
	var viewport_size: Vector2 = get_viewport_rect().size
	var screen_center: Vector2 = viewport_size * 0.5

	if not _star_system.has_method("get_all_celestial_nodes"):
		return {}

	var celestial_nodes: Array = _star_system.call("get_all_celestial_nodes")

	var best_score: float = INF
	var best_data: Dictionary = {}

	for body_node in celestial_nodes:
		if not is_instance_valid(body_node):
			continue

		var world_pos: Vector3 = body_node.global_position
		if camera.is_position_behind(world_pos):
			continue

		var screen_pos: Vector2 = camera.unproject_position(world_pos)
		var on_screen: bool = screen_pos.x >= 0.0 and screen_pos.x <= viewport_size.x \
			and screen_pos.y >= 0.0 and screen_pos.y <= viewport_size.y
		if not on_screen:
			continue

		var distance_to_center: float = screen_pos.distance_to(screen_center)
		if distance_to_center < best_score:
			var radius_m: float = body_node.call("get_radius") if body_node.has_method("get_radius") else 80.0
			var landscape_type: String = body_node.call("get_landscape_type") if body_node.has_method("get_landscape_type") else "unknown"

			best_score = distance_to_center
			best_data = {
				"node": body_node,
				"position": world_pos,
				"radius_m": radius_m,
				"landscape_type": landscape_type,
				"screen_pos": screen_pos,
			}

	return best_data

func _update_frame(target: Dictionary) -> void:
	var world_pos: Vector3 = target.get("position", Vector3.ZERO)
	var radius_m: float = target.get("radius_m", 0.0)
	var screen_pos: Vector2 = target.get("screen_pos", Vector2.ZERO)

	var distance_to_camera: float = world_pos.distance_to(camera.global_position)
	var screen_radius_px: float = _compute_screen_radius(world_pos, radius_m, distance_to_camera)
	screen_radius_px = clamp(screen_radius_px, min_screen_radius_px, max_screen_radius_px)

	_position_corner(_corner_top_left, screen_pos, Vector2(-1, -1), screen_radius_px)
	_position_corner(_corner_top_right, screen_pos, Vector2(1, -1), screen_radius_px)
	_position_corner(_corner_bottom_left, screen_pos, Vector2(-1, 1), screen_radius_px)
	_position_corner(_corner_bottom_right, screen_pos, Vector2(1, 1), screen_radius_px)

	if _info_label:
		var body_node: Node = target.get("node")
		var display_name: String = _get_display_name(body_node)
		var landscape_type: String = target.get("landscape_type", "unknown")
		_info_label.text = "%s\n%s\n%.0f m" % [display_name, landscape_type, distance_to_camera]
		_info_label.position = screen_pos - _info_label.size * 0.5

## Placeholder until the name generator exists - stable per body via
## instance ID so it doesn't flicker between different fake names each frame.
func _get_display_name(body_node: Node) -> String:
	if body_node == null:
		return "???"
	if body_node.has_method("get_display_name"):
		return body_node.call("get_display_name")
	return "Unknown Body"
	
## Projects the sphere's world radius to a screen-space pixel radius by
## unprojecting a point offset from the center by radius_m along the
## camera's right vector, then measuring the resulting screen distance.
func _compute_screen_radius(world_pos: Vector3, radius_m: float, distance_to_camera: float) -> float:
	if distance_to_camera < 0.01:
		return max_screen_radius_px

	var right: Vector3 = camera.global_transform.basis.x
	var edge_world_pos: Vector3 = world_pos + right * radius_m
	var center_screen: Vector2 = camera.unproject_position(world_pos)
	var edge_screen: Vector2 = camera.unproject_position(edge_world_pos)
	return center_screen.distance_to(edge_screen)

func _position_corner(corner: Control, screen_pos: Vector2, dir: Vector2, screen_radius_px: float) -> void:
	if corner == null:
		return
	var offset: Vector2 = dir * (screen_radius_px - corner_inset_px)
	corner.position = screen_pos + offset - corner.size * 0.5

func _on_ui_color_changed(color: Color) -> void:
	if _corner_top_left:
		_corner_top_left.self_modulate = color
	if _corner_top_right:
		_corner_top_right.self_modulate = color
	if _corner_bottom_left:
		_corner_bottom_left.self_modulate = color
	if _corner_bottom_right:
		_corner_bottom_right.self_modulate = color
	if _info_label:
		_info_label.self_modulate = color

func _find_hud_controller() -> HudController:
	var node: Node = get_parent()
	while node:
		if node is HudController:
			return node
		node = node.get_parent()
	return null
