extends RefCounted

static func heights(radius: float) -> Dictionary:
	var change: float = clampf(radius * 0.05, 20000.0, 200000.0)
	return {"switch_m": change, "prepare_m": maxf(change * 3.0, change + 500000.0)}

# Margin matches original safe_step: radius+.25 and entry-.25 stop at H-.5m.
static func entry_guard(offset: LkPosition64, radius: float) -> Dictionary:
	return {"center": [-offset.x, -offset.y, -offset.z], "radius": radius + float(heights(radius)["switch_m"]) - 1.0}

static func rows(entries: Array[Dictionary], parent_slot: int, states: Dictionary, active_id: String, observer: LkPosition64) -> Array[Dictionary]:
	var positions: Dictionary = {}
	for state: Dictionary in states.get("bodies", []):
		positions[state["id"]] = state["position_m"]
	var result: Array[Dictionary] = []
	if not positions.has(active_id):
		return result
	var a: Array = positions[active_id]
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		if int(entry["planet_slot"]) != parent_slot or not positions.has(entry["id"]):
			continue
		var b: Array = positions[entry["id"]]
		var x: float = observer.x
		var y: float = observer.y
		var z: float = observer.z
		if entry["id"] != active_id:
			x -= float(b[0]) - float(a[0])
			y -= float(b[1]) - float(a[1])
			z -= float(b[2]) - float(a[2])
		var gap: float = sqrt(x * x + y * y + z * z) - float(entry["body"]["radius_m"])
		result.append({"index": index, "label": entry["label"], "gap": gap, "planet": int(entry["moon_slot"]) < 0, "active": entry["id"] == active_id})
	result.sort_custom(func(a_row: Dictionary, b_row: Dictionary) -> bool:
		if a_row["planet"] != b_row["planet"]:
			return a_row["planet"]
		if a_row["gap"] == b_row["gap"]:
			return a_row["index"] < b_row["index"]
		return a_row["gap"] < b_row["gap"])
	return result
