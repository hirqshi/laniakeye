extends Control
class_name SystemMap

## Упрощённая карта звёздной системы в углу экрана: звезда в центре,
## орбиты нарисованы процедурно (Line2D circles), планеты - иконки разного
## размера на своих орбитах, плюс иконка "ты здесь" (игрок или корабль,
## смотря что сейчас активно).
##
## Видна ВСЕГДА (не только в корабле) - позиция "ты здесь" берётся из
## ship, если пилотируешь, иначе из player.
##
## МАСШТАБ: реальные orbit_distance_m маппятся на радиус карты через
## sqrt() - линейный маппинг сжал бы близкие орбиты в кучу, если дальняя
## планета намного дальше ближней. sqrt - стандартный компромисс для
## orrery-style мини-карт: сохраняет относительный порядок дистанций,
## не даёт дальним телам вытеснять ближние в невидимую точку у центра.
##
## Все точки (планеты, звезда, "ты здесь") - TextureRect с назначаемой
## текстурой, а не ColorRect/примитивы - Line2D остаётся единственным
## Node2D-элементом (нужен для процедурных окружностей орбит), все
## остальные визуальные элементы - Control-дерево, чтобы не мешать две
## разные системы координат в одном компоненте.

@export var planet_icon_texture: Texture2D
@export var star_icon_texture: Texture2D
@export var player_icon_texture: Texture2D

@export var map_radius_px: float = 90.0
@export var star_dot_radius_px: float = 5.0
@export var planet_dot_min_radius_px: float = 2.5
@export var planet_dot_max_radius_px: float = 7.0
@export var player_icon_radius_px: float = 4.0
@export var orbit_line_width: float = 1.0
@export var orbit_circle_points: int = 48

var _star_system: Node3D
var _player: Node3D
var _ship: Node3D
var _is_piloting_ship: bool = false

var _orbit_lines: Array[Line2D] = []
var _planet_dots: Array[TextureRect] = []
var _player_icon: TextureRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_icon = _make_icon(player_icon_texture, player_icon_radius_px)
	add_child(_player_icon)

	var hud: HudController = _find_hud_controller()
	if hud:
		hud.ui_color_changed.connect(_on_ui_color_changed)
		_on_ui_color_changed(hud.ui_color)

## Вызывается извне (World) один раз после спавна.
func setup(star_system: Node3D, player: Node3D, ship: Node3D) -> void:
	_star_system = star_system
	_player = player
	_ship = ship
	_rebuild_orbits()

func set_piloting_ship(value: bool) -> void:
	_is_piloting_ship = value

func _process(_delta: float) -> void:
	if _star_system == null:
		return
	_update_planet_positions()
	_update_player_icon()

## Builds the static orbit rings + one icon per planet, ONCE, based on
## system_data. Called from setup() - orbit radii don't change at runtime,
## only orbit_angle_rad does (handled per-frame in _update_planet_positions).
func _rebuild_orbits() -> void:
	for line in _orbit_lines:
		line.queue_free()
	for dot in _planet_dots:
		dot.queue_free()
	_orbit_lines.clear()
	_planet_dots.clear()

	if _star_system == null:
		return
	var system_data: SystemData = _star_system.get("system_data")
	if system_data == null or system_data.planets.is_empty():
		return

	var max_orbit_m: float = 0.0
	for planet_data in system_data.planets:
		max_orbit_m = max(max_orbit_m, planet_data.orbit_distance_m)
	if max_orbit_m <= 0.0:
		max_orbit_m = 1.0

	var center: Vector2 = size * 0.5

	for planet_data in system_data.planets:
		var orbit_radius_px: float = _distance_to_map_radius(planet_data.orbit_distance_m, max_orbit_m)

		var orbit_line: Line2D = Line2D.new()
		orbit_line.width = orbit_line_width
		orbit_line.default_color = Color(1, 1, 1, 0.25)
		for i in range(orbit_circle_points + 1):
			var angle: float = TAU * float(i) / float(orbit_circle_points)
			orbit_line.add_point(center + Vector2(cos(angle), sin(angle)) * orbit_radius_px)
		add_child(orbit_line)
		_orbit_lines.append(orbit_line)

		var dot_radius_px: float = lerp(planet_dot_min_radius_px, planet_dot_max_radius_px, clamp(planet_data.radius_m / 200.0, 0.0, 1.0))
		var dot: TextureRect = _make_icon(planet_icon_texture, dot_radius_px)
		add_child(dot)
		_planet_dots.append(dot)

	var star_dot: TextureRect = _make_icon(star_icon_texture, star_dot_radius_px)
	star_dot.position = center - star_dot.size * 0.5
	add_child(star_dot)

func _update_planet_positions() -> void:
	var system_data: SystemData = _star_system.get("system_data")
	if system_data == null:
		return

	var max_orbit_m: float = 0.0
	for planet_data in system_data.planets:
		max_orbit_m = max(max_orbit_m, planet_data.orbit_distance_m)
	if max_orbit_m <= 0.0:
		max_orbit_m = 1.0

	var center: Vector2 = size * 0.5

	for i in range(min(_planet_dots.size(), system_data.planets.size())):
		var planet_data: PlanetData = system_data.planets[i]
		var dot: TextureRect = _planet_dots[i]
		if not is_instance_valid(dot):
			continue

		var orbit_radius_px: float = _distance_to_map_radius(planet_data.orbit_distance_m, max_orbit_m)
		var map_pos: Vector2 = center + Vector2(cos(planet_data.orbit_angle_rad), sin(planet_data.orbit_angle_rad)) * orbit_radius_px
		dot.position = map_pos - dot.size * 0.5

func _update_player_icon() -> void:
	if _player_icon == null:
		return

	var tracked_body: Node3D = _ship if _is_piloting_ship else _player
	if tracked_body == null or not is_instance_valid(tracked_body) or _star_system == null:
		_player_icon.visible = false
		return

	_player_icon.visible = true

	var system_data: SystemData = _star_system.get("system_data")
	var max_orbit_m: float = 1.0
	if system_data:
		for planet_data in system_data.planets:
			max_orbit_m = max(max_orbit_m, planet_data.orbit_distance_m)

	var star_center: Vector3 = _star_system.global_position
	var offset_world: Vector3 = tracked_body.global_position - star_center
	var distance_m: float = offset_world.length()
	var angle_rad: float = atan2(offset_world.z, offset_world.x)

	var radius_px: float = _distance_to_map_radius(distance_m, max_orbit_m)
	var center: Vector2 = size * 0.5
	var map_pos: Vector2 = center + Vector2(cos(angle_rad), sin(angle_rad)) * radius_px
	_player_icon.position = map_pos - _player_icon.size * 0.5

## sqrt scaling keeps close orbits from bunching up near the center while
## still clamping everything to map_radius_px - see class comment.
func _distance_to_map_radius(distance_m: float, max_distance_m: float) -> float:
	var ratio: float = clamp(distance_m / max_distance_m, 0.0, 1.0)
	return sqrt(ratio) * map_radius_px

## Creates a TextureRect icon. If no texture is assigned, falls back to a
## plain white 1x1 texture stretched to size, so the map still shows
## something before art is ready - swap in real icons via the exported
## texture fields whenever they're ready.
func _make_icon(texture: Texture2D, radius_px: float) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.texture = texture if texture else _fallback_texture()
	icon.size = Vector2.ONE * radius_px * 2.0
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _fallback_texture() -> Texture2D:
	var image: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)

func _on_ui_color_changed(color: Color) -> void:
	for line in _orbit_lines:
		line.default_color = Color(color.r, color.g, color.b, 0.25)
	for dot in _planet_dots:
		dot.modulate = color
	if _player_icon:
		_player_icon.modulate = color

func _find_hud_controller() -> HudController:
	var node: Node = get_parent()
	while node:
		if node is HudController:
			return node
		node = node.get_parent()
	return null
