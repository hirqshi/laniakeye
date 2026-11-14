class_name DistantBodyRenderer
extends Node3D

## Renders celestial bodies too far from the camera for Camera3D.far to
## safely reach (float32 precision breaks down well before 500M meters -
## see rendering_light_culler frustum errors at extreme far-plane
## distances) as simplified proxy meshes placed directly in the SAME
## World3D as everything else, just on a compressed distance along the
## real direction to each body.
##
## NO SubViewport, NO second camera, NO custom background shader - this
## is plain geometry in the normal scene graph. Depth testing, lighting,
## and occlusion against the ship/terrain all just work for free, because
## proxies are real objects competing for the same depth buffer as
## everything else. The ONLY trick is distance compression: true
## direction is preserved exactly, only the distance magnitude is
## logarithmically squeezed so a body a billion meters away still ends
## up within near_limit_m + a few hundred meters of the camera.

@export var proxy_mesh_scene: PackedScene

## Bodies closer than this use their TRUE distance - no compression at
## all, so there's no visible pop where proxies hand off to the real
## planet.gd mesh as the player approaches.
@export_range(1000.0, 200_000.0, 1000.0, "suffix:m") var near_limit_m: float = 50_000.0

## Controls how aggressively distances beyond near_limit_m are
## compressed. Larger = flatter falloff, smaller = tighter squeeze.
@export_range(10_000.0, 10_000_000.0, 10_000.0, "suffix:m") var log_scale_m: float = 500_000.0

var _main_camera: Camera3D
var _proxies: Dictionary[Node3D, MeshInstance3D] = {}


func set_main_camera(camera: Camera3D) -> void:
	_main_camera = camera


func get_main_camera() -> Camera3D:
	return _main_camera


func update_bodies(
	bodies: Array[Node3D],
	radii_m: Dictionary[Node3D, float],
	colors: Dictionary[Node3D, Color],
	textures: Dictionary[Node3D, Texture2D]
) -> void:
	if _main_camera == null or not is_instance_valid(_main_camera):
		return

	var seen: Dictionary[Node3D, bool] = {}

	for body in bodies:
		if not is_instance_valid(body):
			continue
		seen[body] = true

		var true_offset: Vector3 = body.global_position - _main_camera.global_position
		var true_distance_m: float = true_offset.length()
		if true_distance_m < 0.001:
			continue

		var direction: Vector3 = true_offset / true_distance_m
		var compressed_distance_m: float = _compress_distance(true_distance_m)

		var proxy: MeshInstance3D = _get_or_create_proxy(
			body,
			colors.get(body, Color.WHITE),
			textures.get(body)
		)
		if proxy == null:
			continue

		proxy.global_position = _main_camera.global_position + direction * compressed_distance_m

		var true_radius_m: float = radii_m.get(body, 50.0)
		var compression_ratio: float = compressed_distance_m / true_distance_m
		proxy.scale = Vector3.ONE * true_radius_m * compression_ratio

	_cleanup_unseen(seen)


func _compress_distance(true_distance_m: float) -> float:
	if true_distance_m <= near_limit_m:
		return true_distance_m
	var excess: float = true_distance_m - near_limit_m
	return near_limit_m + log_scale_m * log(1.0 + excess / log_scale_m)


func _get_or_create_proxy(
	body: Node3D,
	albedo_color: Color,
	albedo_texture: Texture2D
) -> MeshInstance3D:
	if _proxies.has(body):
		return _proxies[body]

	if proxy_mesh_scene == null:
		return null

	var proxy_node: Node = proxy_mesh_scene.instantiate()
	add_child(proxy_node)

	var proxy_mesh: MeshInstance3D = proxy_node as MeshInstance3D
	if proxy_mesh == null:
		proxy_mesh = proxy_node.find_child("*", true, false) as MeshInstance3D

	if proxy_mesh != null:
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = albedo_color
		if albedo_texture != null:
			material.albedo_texture = albedo_texture
		proxy_mesh.material_override = material

	_proxies[body] = proxy_mesh
	return proxy_mesh


func _cleanup_unseen(seen: Dictionary[Node3D, bool]) -> void:
	var stale_keys: Array[Node3D] = []
	for body in _proxies.keys():
		if not seen.has(body) or not is_instance_valid(body):
			stale_keys.append(body)

	for body in stale_keys:
		var proxy: MeshInstance3D = _proxies[body]
		if is_instance_valid(proxy):
			proxy.queue_free()
		_proxies.erase(body)
