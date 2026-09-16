extends Label
class_name SpeedLabel

## Показывает текущую скорость - персонажа (пешком/в невесомости) или
## корабля (когда игрок пилотирует). Режим переключается вместе с тем же
## is_piloting_ship флагом, что скрывает ShipMarker.
##
## Скорость читается напрямую из CharacterBody3D.velocity каждый кадр -
## оба контроллера уже считают её честно каждый физический тик, плодить
## отдельный сигнал "скорость изменилась" ради одного лейбла избыточно.

@export var speed_unit_suffix: String = " m/s"
@export var decimals: int = 1

var _player: CharacterBody3D
var _ship: CharacterBody3D
var _is_piloting_ship: bool = false

func _ready() -> void:
	var hud: HudController = _find_hud_controller()
	if hud:
		hud.ui_color_changed.connect(_on_ui_color_changed)
		_on_ui_color_changed(hud.ui_color)

## Вызывается извне (World) один раз после спавна.
func setup(player: CharacterBody3D, ship: CharacterBody3D) -> void:
	_player = player
	_ship = ship

func set_piloting_ship(value: bool) -> void:
	_is_piloting_ship = value

func _process(_delta: float) -> void:
	var body: CharacterBody3D = _ship if _is_piloting_ship else _player
	if body == null or not is_instance_valid(body):
		text = ""
		return

	var speed_mps: float = body.velocity.length()
	text = "%.*f%s" % [decimals, speed_mps, speed_unit_suffix]

func _on_ui_color_changed(color: Color) -> void:
	self_modulate = color

func _find_hud_controller() -> HudController:
	var node: Node = get_parent()
	while node:
		if node is HudController:
			return node
		node = node.get_parent()
	return null
