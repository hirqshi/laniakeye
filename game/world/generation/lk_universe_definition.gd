class_name LkUniverseDefinition
extends Resource

const Identity = preload("res://game/world/generation/lk_world_identity.gd")

# Development seed, not yet the final release universe.
@export var universe_seed: String = "laniakeye-development-v1"
@export var catalog_version: int = 1
@export var terrain_version: int = 1
@export var geology_version: int = 1
@export var materials_version: int = 1


func get_universe_id() -> String:
	return Identity.universe_id(universe_seed)
