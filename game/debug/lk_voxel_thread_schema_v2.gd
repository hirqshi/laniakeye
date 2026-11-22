class_name LkVoxelThreadSchemaV2
extends RefCounted

static func resolve(names: Array) -> Dictionary:
	var found: Dictionary = {"minimum": [], "margin": [], "ratio": [], "maximum": []}
	for raw in names:
		var name: String = String(raw)
		if not name.begins_with("voxel/threads/") or not name.contains("count"):
			continue
		var leaf: String = name.get_file().to_lower()
		if leaf in ["minimum", "min"]:
			found["minimum"].append(name)
		elif leaf in ["maximum", "max"]:
			found["maximum"].append(name)
		elif leaf.contains("margin") and leaf.contains("max"):
			found["margin"].append(name)
		elif leaf.contains("ratio") and leaf.contains("max"):
			found["ratio"].append(name)
	var result: Dictionary = {}
	for kind: String in found:
		var values: Array = found[kind]
		result[kind] = values[0] if values.size() == 1 else ""
		result[kind + "_matches"] = values
	result["can_cap"] = result["margin"] != "" or result["ratio"] != "" or result["maximum"] != ""
	return result

static func queue_headroom(generation: int, meshing: int, main: int, limit: int = 16) -> bool:
	return (generation < 0 or generation <= limit) and (meshing < 0 or meshing <= limit) and (main < 0 or main <= limit)
