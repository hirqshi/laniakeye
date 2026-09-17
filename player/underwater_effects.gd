class_name UnderwaterEffects
extends Node

const FADE_SPEED: float = 3.0
const MAX_UNDERWATER_ALPHA: float = 0.6

@export var player: CharacterBody3D
@export var tint_color_rect: ColorRect

var _tint_material: ShaderMaterial
var _current_tint_alpha: float = 0.0
var _target_tint_alpha: float = 0.0


func _ready() -> void:
	if tint_color_rect != null:
		_tint_material = tint_color_rect.material as ShaderMaterial


func _process(delta: float) -> void:
	if player == null:
		return

	var gravity_source: Node3D = player.get_current_gravity_source()
	var is_underwater: bool = false

	if gravity_source != null and is_instance_valid(gravity_source) and gravity_source.has_method("is_point_underwater"):
		is_underwater = gravity_source.call("is_point_underwater", player.global_position)

	_target_tint_alpha = MAX_UNDERWATER_ALPHA if is_underwater else 0.0
	_current_tint_alpha = move_toward(_current_tint_alpha, _target_tint_alpha, FADE_SPEED * delta)

	if _tint_material == null:
		return

	_tint_material.set_shader_parameter("tint_alpha", _current_tint_alpha)

	if is_underwater and gravity_source.has_method("get_water_gradient"):
		var water_gradient: Gradient = gravity_source.call("get_water_gradient")
		var tint: Color = water_gradient.sample(0.5) if water_gradient != null else Color(0.1, 0.3, 0.4)
		_tint_material.set_shader_parameter("tint_color", tint)
