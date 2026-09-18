extends CanvasLayer

@export var resume_button: Button
@export var save_and_quit_button: Button
@export var quit_button: Button
@export var star_system: Node3D

const MAIN_MENU_SCENE_PATH: String = "res://ui/menus/main_menu.tscn"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	MouseCaptureManager.set_ui_active(false)

	if resume_button != null:
		resume_button.pressed.connect(_toggle)

	if save_and_quit_button != null:
		save_and_quit_button.pressed.connect(_on_save_and_quit_pressed)

	if quit_button != null:
		quit_button.pressed.connect(_on_quit_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	MouseCaptureManager.set_ui_active(visible)

func _on_save_and_quit_pressed() -> void:
	if is_instance_valid(star_system):
		SaveManager.save_seed(int(star_system.get("system_seed")))

	get_tree().paused = false
	MouseCaptureManager.set_ui_active(true)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)

func _on_quit_pressed() -> void:
	get_tree().paused = false
	MouseCaptureManager.set_ui_active(true)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
