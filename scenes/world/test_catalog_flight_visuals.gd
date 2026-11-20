extends "res://scenes/world/test_catalog_auto_surface.gd"

const VisualBridge = preload("res://world/rendering/lk_flight_visual_bridge.gd")
var _flight_visual_bridge: VisualBridge

func _load_target(index: int) -> void:
	super._load_target(index)
	if not _initialised or _failed or is_instance_valid(_flight_visual_bridge):
		return
	_flight_visual_bridge = VisualBridge.new()
	_flight_visual_bridge.name = "FlightVisualBridge"
	add_child(_flight_visual_bridge)
	if not _flight_visual_bridge.configure(self, _catalog_far_node, _stellar_light_node, _player.player_camera):
		_fail_gate("cannot configure flight visual bridge")
		return
	print("FlightVisuals: ATTACH depth-driven fallback, disk sunlight isolated on layer20, per-hit irradiance")

func _close_local_world() -> void:
	if is_instance_valid(_flight_visual_bridge):
		remove_child(_flight_visual_bridge)
		_flight_visual_bridge.queue_free()
		_flight_visual_bridge = null
	super._close_local_world()

func _process(delta: float) -> void:
	super._process(delta)
	if _initialised and _flight_show_telemetry:
		_label.text += "\nFLIGHT VISUALS: no distance cutout | disk sun independent of observer"

func _unhandled_input(event: InputEvent) -> void:
	if _initialised and event is InputEventKey and event.pressed and not event.echo and event.alt_pressed and event.keycode == KEY_B:
		if is_instance_valid(_catalog_far_node):
			_catalog_far_node.set_albedo_debug(not _catalog_far_node.is_albedo_debug())
			print("FlightVisuals: ALBEDO_DEBUG %s" % _catalog_far_node.is_albedo_debug())
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)
