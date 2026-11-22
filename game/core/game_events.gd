class_name LkGameEvents
extends RefCounted
## Event bus shared by all game systems. Owned by LkGame and passed to components.
## Prefer signals here over direct references between systems.

@warning_ignore("unused_signal")
signal body_activated(body_id: StringName)
@warning_ignore("unused_signal")
signal transfer_started(from_body_id: StringName, to_body_id: StringName)
@warning_ignore("unused_signal")
signal transfer_finished(body_id: StringName)
@warning_ignore("unused_signal")
signal player_mode_changed(from_mode: int, to_mode: int, reason: String)
@warning_ignore("unused_signal")
signal terrain_state_changed(from_state: int, to_state: int, reason: String)
@warning_ignore("unused_signal")
signal edit_session_finished(body_id: StringName, edit_mode: StringName, revision_from: int, revision_to: int)
