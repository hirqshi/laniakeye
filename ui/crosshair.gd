extends Control
class_name Crosshair

## Прицел в центре экрана + рамка вокруг него с небольшим отставанием.
## Прицел всегда жёстко в центре. Рамка не мгновенно следует за камерой -
## при резких поворотах она на мгновение "отстаёт", затем догоняет
## прицел с экспоненциальным сглаживанием (та же lag-модель, что позже
## переиспользуем в PlanetTargetFrame).
##
## Отставание считается не по позиции мыши (мышь не двигает камеру от
## центра экрана - камера вращается, курсор скрыт), а по угловой скорости
## поворота камеры за кадр: чем резче поворот, тем сильнее рамка
## "выталкивается" в сторону, откуда мы только что довернули, и потом
## возвращается к центру.

@export var camera: Camera3D
@export var lag_recovery_speed: float = 8.0
@export var lag_push_strength: float = 900.0
@export var lag_max_offset_px: float = 40.0
@export var invert_x: bool = false
@export var invert_y: bool = false

var _frame_offset: Vector2 = Vector2.ZERO
var _last_camera_basis: Basis = Basis.IDENTITY
var _has_last_basis: bool = false

@onready var _dot: Control = $Dot
@onready var _frame: Control = $Frame

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _dot:
		_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _frame:
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hud: HudController = _find_hud_controller()
	if hud:
		hud.ui_color_changed.connect(_on_ui_color_changed)
		_on_ui_color_changed(hud.ui_color)

## Вызывается извне (World), когда меняется активная камера
## (вход/выход из корабля) - см. тот же паттерн, что и ShipMarker.setup().
func set_camera(new_camera: Camera3D) -> void:
	camera = new_camera
	_has_last_basis = false

func _process(delta: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var screen_center: Vector2 = viewport_size * 0.5

	if _dot:
		_dot.position = screen_center - _dot.size * 0.5

	_update_lag(delta)

	if _frame:
		_frame.position = screen_center - _frame.size * 0.5 + _frame_offset

func _update_lag(delta: float) -> void:
	if camera == null:
		_frame_offset = _frame_offset.lerp(Vector2.ZERO, clamp(lag_recovery_speed * delta, 0.0, 1.0))
		return

	var current_basis: Basis = camera.global_transform.basis

	if not _has_last_basis:
		_last_camera_basis = current_basis
		_has_last_basis = true
		return

	var delta_basis: Basis = _last_camera_basis.inverse() * current_basis
	var delta_rotation: Quaternion = delta_basis.get_rotation_quaternion()

	# small-angle approx: yaw/pitch component of the rotation this frame.
	# sign convention tuned against actual screen behavior, not assumed -
	# invert_x/invert_y let you flip either axis from the inspector
	# without touching the math if your camera setup differs.
	var turn_yaw: float = delta_rotation.y
	var turn_pitch: float = delta_rotation.x

	var sign_x: float = -1.0 if invert_x else 1.0
	var sign_y: float = -1.0 if invert_y else 1.0

	var push: Vector2 = Vector2(turn_yaw * sign_x, turn_pitch * sign_y) * lag_push_strength
	_frame_offset += push
	_frame_offset = _frame_offset.lerp(Vector2.ZERO, clamp(lag_recovery_speed * delta, 0.0, 1.0))

	if _frame_offset.length() > lag_max_offset_px:
		_frame_offset = _frame_offset.normalized() * lag_max_offset_px

	_last_camera_basis = current_basis

func _on_ui_color_changed(color: Color) -> void:
	if _dot:
		_dot.self_modulate = color
	if _frame:
		_frame.self_modulate = color

func _find_hud_controller() -> HudController:
	var node: Node = get_parent()
	while node:
		if node is HudController:
			return node
		node = node.get_parent()
	return null
