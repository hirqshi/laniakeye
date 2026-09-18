extends Node

const SPAWN_ANCHOR_GROUP: StringName = &"creature_spawn_anchor"

var _active_anchor: Node3D

func set_active_anchor(anchor: Node3D) -> void:
	if anchor == null:
		push_warning(
			"SpawnAnchorService: attempted to set a null anchor"
		)
		return

	if _active_anchor != null:
		if is_instance_valid(_active_anchor):
			_active_anchor.remove_from_group(
				SPAWN_ANCHOR_GROUP
			)

	_active_anchor = anchor

	if not _active_anchor.is_in_group(SPAWN_ANCHOR_GROUP):
		_active_anchor.add_to_group(SPAWN_ANCHOR_GROUP)

func clear_active_anchor(anchor: Node3D) -> void:
	if anchor == null:
		return

	if anchor.is_in_group(SPAWN_ANCHOR_GROUP):
		anchor.remove_from_group(SPAWN_ANCHOR_GROUP)

	if _active_anchor == anchor:
		_active_anchor = null

func get_active_anchor() -> Node3D:
	if _active_anchor == null:
		return null

	if not is_instance_valid(_active_anchor):
		_active_anchor = null
		return null

	return _active_anchor
