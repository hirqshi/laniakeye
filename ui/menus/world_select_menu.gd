extends Control

signal closed

@export var background_dim: ColorRect
@export var rows_scroll: ScrollContainer
@export var rows_root: Control
@export var empty_label: Label
@export var back_button: Button
@export var save_system_row_scene: PackedScene

@export_range(10.0, 200.0, 1.0, "suffix:px")
var row_spacing_px: float = 62.0

const GAME_SCENE_PATH: String = "res://scenes/world.tscn"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	if back_button != null:
		back_button.pressed.connect(_on_back_button_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

func open() -> void:
	visible = true
	_rebuild_rows()

func _close() -> void:
	visible = false
	closed.emit()

func _rebuild_rows() -> void:
	if rows_root == null:
		push_error("WorldSelectMenu: Rows Root is not assigned")
		return

	for child: Node in rows_root.get_children():
		child.queue_free()

	var saves: Array[Dictionary] = SaveManager.get_saved_seeds()

	if empty_label != null:
		empty_label.visible = saves.is_empty()

	rows_root.custom_minimum_size = Vector2(
		0.0,
		row_spacing_px * float(saves.size())
	)

	if save_system_row_scene == null:
		push_error("WorldSelectMenu: Save System Row Scene is not assigned")
		return

	for row_index: int in range(saves.size()):
		var row: SaveSystemRow = (
			save_system_row_scene.instantiate() as SaveSystemRow
		)

		if row == null:
			push_error(
				"WorldSelectMenu: Save System Row Scene root must be SaveSystemRow"
			)
			return

		rows_root.add_child(row)
		row.position = Vector2(0.0, row_spacing_px * float(row_index))
		row.setup(saves[row_index])

		row.load_requested.connect(_on_load_requested)
		row.delete_requested.connect(_on_delete_requested)

func _on_load_requested(seed_value: int) -> void:
	SaveManager.pending_seed = seed_value
	MouseCaptureManager.set_ui_active(false)
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

func _on_delete_requested(seed_value: int) -> void:
	SaveManager.delete_seed(seed_value)
	_rebuild_rows()

func _on_back_button_pressed() -> void:
	_close()
