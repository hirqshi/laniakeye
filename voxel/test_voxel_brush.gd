extends Node

@export_range(1.0, 4.0, 0.25) var brush_radius_m: float = 1.5
@export var reach_m: float = 8.0
@export var edit_interval_s: float = 0.25

var _terrain: VoxelLodTerrain
var _body: CharacterBody3D
var _camera: Camera3D
var _capsule: CapsuleShape3D
var _tool: VoxelToolLodTerrain
var _marker: MeshInstance3D
var _material: StandardMaterial3D
var _label: Label
var _cooldown: float = 0.0
var _ready_for_edits: bool = false
var _requests: int = 0
var _last: String = "No edits; changes are NOT saved"


func _ready() -> void:
	call_deferred("_initialize")


func _initialize() -> void:
	var sandbox: Node = get_parent()
	_terrain = sandbox.get("_terrain") as VoxelLodTerrain
	_body = sandbox.get("_body") as CharacterBody3D
	_camera = sandbox.get("_camera") as Camera3D
	_capsule = sandbox.get("_capsule") as CapsuleShape3D
	if _terrain == null or _body == null or _camera == null or _capsule == null:
		push_error("VoxelBrush: missing physics sandbox dependencies")
		return
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_SDF
	_tool.sdf_scale = 1.0
	_tool.sdf_strength = 1.0
	_tool.set_raycast_normal_enabled(true)
	_tool.set_raycast_binary_search_iterations(8)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(0.1, 1.0, 0.8)
	_marker = MeshInstance3D.new()
	_marker.name = "BrushPreview"
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wire: ImmediateMesh = ImmediateMesh.new()
	wire.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	for plane: int in range(3):
		for i: int in range(64):
			var a: float = TAU * float(i) / 64.0
			var b: float = TAU * float(i + 1) / 64.0
			if plane == 0:
				wire.surface_add_vertex(Vector3(cos(a), sin(a), 0.0))
				wire.surface_add_vertex(Vector3(cos(b), sin(b), 0.0))
			elif plane == 1:
				wire.surface_add_vertex(Vector3(cos(a), 0.0, sin(a)))
				wire.surface_add_vertex(Vector3(cos(b), 0.0, sin(b)))
			else:
				wire.surface_add_vertex(Vector3(0.0, cos(a), sin(a)))
				wire.surface_add_vertex(Vector3(0.0, cos(b), sin(b)))
	wire.surface_end()
	_marker.mesh = wire
	_marker.visible = false
	sandbox.add_child(_marker)
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 2
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	canvas.add_child(_label)
	var crosshair: Label = Label.new()
	crosshair.text = "+"
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position = get_viewport().get_visible_rect().size * 0.5 - Vector2(5.0, 10.0)
	canvas.add_child(crosshair)
	sandbox.add_child(canvas)
	_ready_for_edits = true
	print("VoxelBrush: LMB dig, RMB build, wheel radius; no persistence")


func _near_capsule(center: Vector3) -> bool:
	var axis: Vector3 = _body.global_basis.y.normalized()
	var half_segment: float = maxf(_capsule.height * 0.5 - _capsule.radius, 0.0)
	var axial: float = clampf((center - _body.global_position).dot(axis), -half_segment, half_segment)
	var closest: Vector3 = _body.global_position + axis * axial
	return center.distance_to(closest) <= brush_radius_m + _capsule.radius + 1.0


func _physics_process(delta: float) -> void:
	if not _ready_for_edits:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_label.position = Vector2(12.0, maxf(get_viewport().get_visible_rect().size.y - 86.0, 180.0))
	_label.text = "LMB dig | RMB build | Wheel radius: %.2f m | reach %.1f m\nEdit requests: %d | %s\nSession only: edits may be lost on unload/restart" % [brush_radius_m, reach_m, _requests, _last]
	_marker.visible = false
	if bool(get_parent().get("_waiting")) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var origin: Vector3 = _camera.global_position
	var direction: Vector3 = -_camera.global_basis.z.normalized()
	var hit: VoxelRaycastResult = _tool.raycast(origin, direction, reach_m)
	if hit == null:
		return
	var normal: Vector3 = hit.normal.normalized()
	if normal.length_squared() < 0.1:
		normal = -direction
	var building: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var digging: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var surface_point: Vector3 = origin + direction * hit.distance
	var center: Vector3 = surface_point + normal * brush_radius_m * (0.25 if building else -0.25)
	var local_center: Vector3 = _terrain.to_local(center)
	var padding: float = brush_radius_m + 3.0
	var area: AABB = AABB(local_center - Vector3.ONE * padding, Vector3.ONE * padding * 2.0)
	var editable: bool = _tool.is_area_editable(area)
	var capsule_blocked: bool = building and _near_capsule(center)
	var within_test: bool = absf(local_center.x) + padding < 240.0 and absf(local_center.y) + padding < 240.0 and absf(local_center.z) + padding < 240.0
	var allowed: bool = editable and within_test and not capsule_blocked
	_marker.visible = true
	_marker.global_position = center
	_marker.scale = Vector3.ONE * brush_radius_m
	_material.albedo_color = Color(0.1, 1.0, 0.8) if allowed else Color(1.0, 0.15, 0.1)
	if not digging and not building:
		return
	if _cooldown > 0.0:
		return
	_cooldown = maxf(edit_interval_s, 0.1)
	if digging and building:
		_last = "Use one mouse button at a time"
		return
	if not allowed:
		_last = "Build blocked near capsule" if capsule_blocked else "Area not loaded or outside test bounds"
		return
	_tool.mode = VoxelTool.MODE_ADD if building else VoxelTool.MODE_REMOVE
	_tool.do_sphere(local_center, brush_radius_m)
	_requests += 1
	var block: Vector3i = Vector3i((local_center / 16.0).floor())
	_last = "%s requested at block %s" % ["BUILD" if building else "DIG", block]
	print("VoxelBrush: ", _last, " center=", local_center, " radius=", brush_radius_m)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			brush_radius_m = minf(brush_radius_m + 0.25, 4.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			brush_radius_m = maxf(brush_radius_m - 0.25, 1.0)
			get_viewport().set_input_as_handled()
