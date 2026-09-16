extends Control
class_name ShipMarker

## Индикатор направления на корабль, когда игрок вне корабля (пешком).
## Если корабль в кадре - маркер стоит в его экранной проекции.
## Если корабль за кадром - маркер прижимается к ближайшему краю экрана в его направлении.
## Маркер никогда не вращается - иконка всегда стоит прямо.
## Полностью скрыт, пока игрок пилотирует корабль (is_piloting_ship == true).
##
## camera и ship не задаются в инспекторе - HUD живёт в отдельной сцене от уровня,
## поэтому зависимости приходят через setup() от того, кто создаёт и HUD, и Ship (обычно World).

@export var edge_margin_px: float = 48.0
@export var alpha_on_screen: float = 0.35
@export var alpha_off_screen: float = 0.7

var _camera: Camera3D
var _ship: Node3D
var _is_piloting_ship: bool = false

@onready var _icon: TextureRect = $Icon

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _icon:
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var hud: HudController = _find_hud_controller()
	if hud:
		hud.ui_color_changed.connect(_on_ui_color_changed)
		_on_ui_color_changed(hud.ui_color)

## Вызывается извне (World) при спавне игрока и корабля,
## а также при смене камеры (вход/выход из корабля).
func setup(camera: Camera3D, ship: Node3D) -> void:
	_camera = camera
	_ship = ship

func clear_ship() -> void:
	_ship = null

## Вызывается извне (World, через сигналы ShipSeat) при посадке/высадке -
## маркер не имеет смысла, пока игрок сам управляет кораблём.
func set_piloting_ship(value: bool) -> void:
	_is_piloting_ship = value

func _process(_delta: float) -> void:
	if _is_piloting_ship or _camera == null or _ship == null or not is_instance_valid(_ship):
		visible = false
		return
	visible = true
	_update_position()

func _update_position() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var screen_center: Vector2 = viewport_size * 0.5
	var ship_pos: Vector3 = _ship.global_position
	var is_behind: bool = _camera.is_position_behind(ship_pos)

	if not is_behind:
		var screen_pos: Vector2 = _camera.unproject_position(ship_pos)
		var on_screen: bool = screen_pos.x >= 0.0 and screen_pos.x <= viewport_size.x \
			and screen_pos.y >= 0.0 and screen_pos.y <= viewport_size.y
		if on_screen:
			_place_on_screen(screen_pos)
			return

	_place_on_edge(ship_pos, screen_center, viewport_size)

func _place_on_screen(screen_pos: Vector2) -> void:
	position = screen_pos - size * 0.5
	modulate.a = alpha_on_screen

func _place_on_edge(ship_pos: Vector3, screen_center: Vector2, viewport_size: Vector2) -> void:
	var to_ship: Vector3 = ship_pos - _camera.global_position
	var right: Vector3 = _camera.global_transform.basis.x
	var up: Vector3 = _camera.global_transform.basis.y
	var forward: Vector3 = -_camera.global_transform.basis.z

	var dir_x: float = to_ship.dot(right)
	var dir_y: float = -to_ship.dot(up)
	var dir_z: float = to_ship.dot(forward)

	if dir_z < 0.0:
		dir_x = -dir_x
		dir_y = -dir_y

	var dir_2d: Vector2 = Vector2(dir_x, dir_y)
	if dir_2d.length_squared() < 0.0001:
		dir_2d = Vector2.DOWN

	dir_2d = dir_2d.normalized()

	var half_w: float = screen_center.x - edge_margin_px
	var half_h: float = screen_center.y - edge_margin_px
	var scale_x: float = half_w / max(absf(dir_2d.x), 0.0001)
	var scale_y: float = half_h / max(absf(dir_2d.y), 0.0001)
	var scale: float = min(scale_x, scale_y)

	var edge_pos: Vector2 = screen_center + dir_2d * scale
	position = edge_pos - size * 0.5
	modulate.a = alpha_off_screen

func _on_ui_color_changed(color: Color) -> void:
	if _icon:
		_icon.self_modulate = color

func _find_hud_controller() -> HudController:
	var node: Node = get_parent()
	while node:
		if node is HudController:
			return node
		node = node.get_parent()
	return null
