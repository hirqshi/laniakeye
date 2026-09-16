extends Node

## Autoload singleton. Owns OS mouse capture state for the whole game.
## Captures on start, releases on Escape, re-captures on click.
## This is intentionally the ONLY place that touches Input.mouse_mode -
## gameplay scripts (player, ship, UI) should never set mouse_mode directly,
## so capture behavior stays consistent and easy to change in one spot.

func _ready() -> void:
	capture_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		release_mouse()
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			capture_mouse()

func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func is_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
