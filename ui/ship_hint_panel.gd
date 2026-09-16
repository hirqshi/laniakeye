extends Control
class_name ShipHintPanel

## "R - return to ship" подсказка + дистанция до корабля.
## Видна только когда игрок пешком (не пилотирует корабль) и ссылка на
## ship валидна. Не завязана на прицеливание/наведение - это глобальное
## состояние "ты сейчас не на корабле", в отличие от "E - seat"
## (которая уже реализована в ShipSeat как Label3D в мире, не HUD).

@export var hint_text: String = "R - return to ship"
@export var distance_format: String = "%.0f m"

var _ship: Node3D
var _player: Node3D
var _is_piloting_ship: bool = false

@onready var _hint_label: Label = $HintLabel
@onready var _distance_label: Label = $DistanceLabel

func _ready() -> void:
	if _hint_label:
		_hint_label.text = hint_text
	visible = false

	var hud: HudController = _find_hud_controller()
	if hud:
		hud.ui_color_changed.connect(_on_ui_color_changed)
		_on_ui_color_changed(hud.ui_color)

## Вызывается извне (World) один раз после спавна - оба player и ship уже
## существуют в World, передаются явно, без похода в группы.
func setup(player: Node3D, ship: Node3D) -> void:
	_player = player
	_ship = ship

func set_piloting_ship(value: bool) -> void:
	_is_piloting_ship = value

func _process(_delta: float) -> void:
	if _is_piloting_ship or _ship == null or not is_instance_valid(_ship):
		visible = false
		return

	visible = true
	if _distance_label and _player != null and is_instance_valid(_player):
		var distance_m: float = _player.global_position.distance_to(_ship.global_position)
		_distance_label.text = distance_format % distance_m

func _on_ui_color_changed(color: Color) -> void:
	if _hint_label:
		_hint_label.self_modulate = color
	if _distance_label:
		_distance_label.self_modulate = color

func _find_hud_controller() -> HudController:
	var node: Node = get_parent()
	while node:
		if node is HudController:
			return node
		node = node.get_parent()
	return null
