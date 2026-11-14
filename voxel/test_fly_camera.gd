extends Camera3D

@export var move_speed_m_s: float = 50.0
@export var boost_multiplier: float = 10.0
@export var mouse_sensitivity: float = 0.002

var _pitch_rad: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotation.y -= event.relative.x * mouse_sensitivity
		_pitch_rad = clampf(
			_pitch_rad - event.relative.y * mouse_sensitivity,
			-deg_to_rad(89.0),
			deg_to_rad(89.0)
		)
		rotation.x = _pitch_rad


func _physics_process(delta: float) -> void:
	var input_dir: Vector3 = Vector3(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_down", "move_up"),
		Input.get_axis("move_back", "move_forward")
	)

	var speed: float = move_speed_m_s
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= boost_multiplier

	var move_dir: Vector3 = (global_transform.basis * input_dir).normalized()
	if input_dir.length() > 0.01:
		global_position += move_dir * speed * delta
