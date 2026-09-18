extends CanvasLayer
class_name HudController

## Единая точка входа для HUD: toggle видимости, единый цвет интерфейса
## и раздача world-зависимостей (camera/ship) дочерним HUD-компонентам.
##
## HUD живёт в отдельной сцене от уровня, поэтому camera/ship не экспортируются -
## World (или другой владелец сцены уровня) вызывает set_ship_reference()
## один раз после спавна, а также при смене активной камеры (вход/выход из корабля).
## HudController не лезет во внутренности Ship/Player - только хранит и раздаёт то,
## что ему явно передали.

signal ui_color_changed(color: Color)

@export var ui_color: Color = Color(0.4, 1.0, 0.6, 1.0):
	set(value):
		ui_color = value
		ui_color_changed.emit(ui_color)

@export var root: Control
@export var ship_marker: ShipMarker
@export var crosshair: Crosshair
@export var speed_label: SpeedLabel
@export var planet_target_frame: PlanetTargetFrame
@export var ship_hint_panel: ShipHintPanel
@export var system_map: SystemMap

var _star_system_ref: Node3D
var _leviathan_spawner_ref: LeviathanSpawner

func _ready() -> void:
	if root == null:
		push_warning("HudController: root Control не назначен в инспекторе")
	ui_color_changed.emit(ui_color)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_ui"):
		_toggle_ui()

func _toggle_ui() -> void:
	if root == null:
		return
	root.visible = not root.visible

## Вызывается владельцем сцены уровня (World) после спавна ship/player,
## а также каждый раз при смене активной камеры (сел в корабль / вышел из корабля).

func set_player_and_ship(player: CharacterBody3D, ship: CharacterBody3D) -> void:
	if speed_label:
		speed_label.setup(player, ship)
	if ship_hint_panel:
		ship_hint_panel.setup(player, ship)
	if system_map and _star_system_ref:
		system_map.setup(_star_system_ref, player, ship, _leviathan_spawner_ref)

func clear_ship_reference() -> void:
	if ship_marker:
		ship_marker.clear_ship()

func set_ship_reference(camera: Camera3D, ship: Node3D) -> void:
	if ship_marker:
		ship_marker.setup(camera, ship)
	if crosshair:
		crosshair.set_camera(camera)
	if planet_target_frame:
		planet_target_frame.set_camera(camera)

func set_piloting_ship(value: bool) -> void:
	if ship_marker:
		ship_marker.set_piloting_ship(value)
	if speed_label:
		speed_label.set_piloting_ship(value)
	if planet_target_frame:
		planet_target_frame.set_piloting_ship(value)
	if ship_hint_panel:
		ship_hint_panel.set_piloting_ship(value)
	if system_map:
		system_map.set_piloting_ship(value)

func set_star_system(star_system: Node3D) -> void:
	_star_system_ref = star_system
	if planet_target_frame:
		planet_target_frame.setup(star_system)

## Called by World alongside set_star_system() - kept as a separate
## setter instead of bundling into set_star_system() because the two
## come from different exports on World (star_system vs leviathan_spawner)
## and HudController shouldn't assume they're always set together.
func set_leviathan_spawner(leviathan_spawner: LeviathanSpawner) -> void:
	_leviathan_spawner_ref = leviathan_spawner
