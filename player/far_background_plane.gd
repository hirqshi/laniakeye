class_name FarBackgroundPlane
extends MeshInstance3D

## A large quad that always sits a fixed distance in front of whichever
## camera World marks as active (player or ship seat), displaying the
## DistantBodyRenderer's far-viewport texture. depth_draw_never on its
## material (far_background.gdshader) means it never competes for depth
## with real geometry - it is always drawn behind everything else,
## exactly like a skybox, regardless of the fixed distance below.
##
## World calls set_active_camera() once on spawn and again on every
## seat swap - same pattern as DistantBodyRenderer.set_main_camera(),
## since both need to react to the same camera handoff.

@export var plane_distance_m: float = 10.0
@export var plane_size_m: float = 500.0

var _active_camera: Camera3D

func _ready() -> void:
	mesh = QuadMesh.new()
	(mesh as QuadMesh).size = Vector2.ONE * plane_size_m


func set_active_camera(camera: Camera3D) -> void:
	_active_camera = camera


func _process(_delta: float) -> void:
	if _active_camera == null or not is_instance_valid(_active_camera):
		return

	global_transform.basis = _active_camera.global_transform.basis
	global_position = _active_camera.global_position - _active_camera.global_transform.basis.z * plane_distance_m
