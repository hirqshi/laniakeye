class_name CreatureLocomotionStrategy
extends RefCounted

## Base contract for how a CreatureBody positions itself each physics
## tick. Subclasses own all state for their movement mode; CreatureBody
## just forwards delta and reads back nothing - the strategy writes
## directly to body.global_position / body.global_transform.

func enter(body: CreatureBody) -> void:
	pass

func update(body: CreatureBody, delta: float) -> void:
	pass
