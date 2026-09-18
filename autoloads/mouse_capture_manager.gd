extends Node

## Autoload singleton. Owns OS mouse capture state for the whole game.
## Gameplay uses capture_mouse()/release_mouse().
## Full-screen UI uses set_ui_active(), which prevents a UI click from
## immediately capturing the cursor back into the game.

var _is_ui_active: bool = false

func _ready() -> void:
	capture_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if _is_ui_active:
		return

	if event.is_action_pressed("ui_cancel"):
		release_mouse()
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			capture_mouse()

func set_ui_active(value: bool) -> void:
	_is_ui_active = value

	if _is_ui_active:
		release_mouse()
	else:
		capture_mouse()

func capture_mouse() -> void:
	if _is_ui_active:
		return

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func is_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func is_ui_active() -> bool:
	return _is_ui_active
