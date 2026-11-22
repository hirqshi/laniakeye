extends RefCounted

var entries: Array[Dictionary] = []
var selected: int = -1
var _system_id: String = ""

func configure(layout: Dictionary, active_id: String) -> bool:
	entries.clear()
	selected = -1
	_system_id = ""
	if layout.get("layout_version", -1) != 1 or not layout.has_all(["system_id", "planets"]):
		return false
	for index: int in range(layout["planets"].size()):
		var planet: Dictionary = layout["planets"][index]
		var slot: int = int(planet["body"].get("slot", index))
		_append(planet, slot, -1, "Planet %02d" % (slot + 1))
		for moon_index: int in range(planet["moons"].size()):
			var moon: Dictionary = planet["moons"][moon_index]
			_append(moon, slot, moon_index, "Planet %02d / Moon %02d" % [slot + 1, moon_index + 1])
	_system_id = String(layout["system_id"])
	for index: int in range(entries.size()):
		if entries[index]["id"] != active_id:
			selected = index
			break
	if selected < 0 and not entries.is_empty():
		selected = 0
	return not _system_id.is_empty() and not entries.is_empty()

func _append(entry: Dictionary, planet_slot: int, moon_slot: int, label: String) -> void:
	if entry["body"].get("family", "") == "gas_giant":
		return
	entries.append({"id": String(entry["body"]["id"]), "label": label,
		"planet_slot": planet_slot, "moon_slot": moon_slot,
		"body": entry["body"].duplicate(true), "orbit": entry["orbit"].duplicate(true),
		"spin": entry["spin"].duplicate(true)})

func current() -> Dictionary:
	return entries[selected] if selected >= 0 and selected < entries.size() else {}

func cycle(step: int) -> void:
	if not entries.is_empty():
		selected = posmod(selected + step, entries.size())

# Same manifest recipe as current BodyContext; ID and radius are target-specific.
# Does not call the planet-only resolver, open files, or change the active context.
func target_context(template: Dictionary) -> Dictionary:
	var entry: Dictionary = current()
	if entry.is_empty() or not template.has_all(["manifest", "body", "universe_id", "address", "placement"]):
		return {}
	if template["manifest"].get("body_id", "") != template["body"].get("id", ""):
		return {}
	var manifest: Dictionary = template["manifest"].duplicate(true)
	manifest["body_id"] = entry["id"]
	manifest["radius_m"] = entry["body"]["radius_m"]
	var address: Dictionary = template["address"].duplicate(true)
	address["planet_slot"] = entry["planet_slot"]
	if entry["moon_slot"] >= 0:
		address["moon_slot"] = entry["moon_slot"]
	else:
		address.erase("moon_slot")
	return {"universe_id": template["universe_id"], "body": entry["body"].duplicate(true),
		"orbit": entry["orbit"].duplicate(true), "spin": entry["spin"].duplicate(true),
		"placement": template["placement"].duplicate(true), "address": address, "manifest": manifest}

# Observer is inertial, relative to the ACTIVE body's centre, as in DebugFlight.
# Target axes and both positions come from ONE exact-epoch system snapshot.
func plan(states: Dictionary, active_id: String, observer: LkPosition64, epoch: float) -> Dictionary:
	var entry: Dictionary = current()
	if entry.is_empty() or not is_finite(epoch) or states.get("system_id", "") != _system_id or states.get("time_s", NAN) != epoch:
		return {"ok": false, "error": "scope_or_epoch_mismatch"}
	var active: Dictionary = {}
	var target: Dictionary = {}
	for state: Dictionary in states.get("bodies", []):
		if state["id"] == active_id:
			active = state
		if state["id"] == entry["id"]:
			target = state
	if active.is_empty() or target.is_empty():
		return {"ok": false, "error": "body_state_missing"}
	var a: Array = active["position_m"]
	var b: Array = target["position_m"]
	var x: float = observer.x
	var y: float = observer.y
	var z: float = observer.z
	if active_id != entry["id"]:
		x -= float(b[0]) - float(a[0])
		y -= float(b[1]) - float(a[1])
		z -= float(b[2]) - float(a[2])
	var distance: float = sqrt(x * x + y * y + z * z)
	var radius: float = float(entry["body"]["radius_m"])
	if not is_finite(distance) or distance <= 0.0 or not is_finite(radius) or radius <= 0.0:
		return {"ok": false, "error": "invalid_target_geometry"}
	var sx: float = x / distance * radius
	var sy: float = y / distance * radius
	var sz: float = z / distance * radius
	var axes: Array = target["body_to_system_axes"]
	var fixed: LkPosition64 = LkPosition64.new(
		float(axes[0][0]) * sx + float(axes[0][1]) * sy + float(axes[0][2]) * sz,
		float(axes[1][0]) * sx + float(axes[1][1]) * sy + float(axes[1][2]) * sz,
		float(axes[2][0]) * sx + float(axes[2][1]) * sy + float(axes[2][2]) * sz)
	return {"ok": true, "target_id": entry["id"], "active_id": active_id, "epoch": epoch,
		"distance_m": distance, "height_m": distance - radius, "fixed_surface": fixed}
