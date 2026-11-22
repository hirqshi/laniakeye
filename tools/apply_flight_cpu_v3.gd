extends SceneTree

const EDITS: Array = [
  {
    "path": "res://scenes/world/test_catalog_debug_flight.gd",
    "marker": "FLIGHT_CPU3_HOOKS_V1",
    "pairs": [
      [
        "var _flight_active: bool = false",
        "var flight_cpu_sections_enabled: bool = false\nvar _flight_active: bool = false"
      ],
      [
        "var states: Dictionary = Layout.evaluate(_nav_layout, _universe_clock.now_s())",
        "var states: Dictionary = _flight_system_states()"
      ],
      [
        "func _tick_flight(delta: float) -> void:\n",
        "func _tick_flight(delta: float) -> void:\n\tvar _cpu_us: int = Time.get_ticks_usec() if flight_cpu_sections_enabled else 0\n"
      ],
      [
        "\tif not _place_flight_absolute(_flight_absolute):\n\t\t_fail_gate(\"flight relocation failed\")",
        "\t_cpu_us = _flight_cpu_boundary(\"clock_carry\", _cpu_us)\n\tif not _place_flight_absolute(_flight_absolute):\n\t\t_fail_gate(\"flight relocation failed\")"
      ],
      [
        "\tvar spheres: Array = _flight_spheres()",
        "\t_cpu_us = _flight_cpu_boundary(\"place_before\", _cpu_us)\n\tvar spheres: Array = _flight_spheres()"
      ],
      [
        "\tvar boost: float = 4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0",
        "\t_cpu_us = _flight_cpu_boundary(\"spheres\", _cpu_us)\n\tvar boost: float = 4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0"
      ],
      [
        "\tif not _place_flight_absolute(_flight_absolute):\n\t\t_fail_gate(\"flight relocation failed after movement\")",
        "\t_cpu_us = _flight_cpu_boundary(\"movement_guard\", _cpu_us)\n\tif not _place_flight_absolute(_flight_absolute):\n\t\t_fail_gate(\"flight relocation failed after movement\")"
      ],
      [
        "\t_update_stellar_lighting()\n\t_update_navigation_tick(delta)",
        "\t_cpu_us = _flight_cpu_boundary(\"place_after\", _cpu_us)\n\t_update_stellar_lighting()\n\t_cpu_us = _flight_cpu_boundary(\"lighting\", _cpu_us)\n\t_update_navigation_tick(delta)\n\t_cpu_us = _flight_cpu_boundary(\"navigation\", _cpu_us)"
      ],
      [
        "\tif _flight_landing_requested:\n\t\t_try_flight_landing()\n\nfunc _refuse_flight_landing",
        "\tif _flight_landing_requested:\n\t\t_try_flight_landing()\n\t_cpu_us = _flight_cpu_boundary(\"tail\", _cpu_us)\n\nfunc _refuse_flight_landing"
      ]
    ],
    "append": "\n# FLIGHT_CPU3_HOOKS_V1\nfunc _flight_system_states() -> Dictionary:\n\treturn Layout.evaluate(_nav_layout, _universe_clock.now_s())\n\nfunc _flight_cpu_boundary(section: String, started: int) -> int:\n\tif not flight_cpu_sections_enabled:\n\t\treturn 0\n\tvar now: int = Time.get_ticks_usec()\n\t_flight_cpu_section(section, now - started)\n\treturn now\n\nfunc _flight_cpu_section(_section: String, _elapsed_us: int) -> void:\n\tpass\n"
  },
  {
    "path": "res://scenes/world/test_catalog_debug_navigation.gd",
    "marker": "NAV_CPU3_PROVIDER_V1",
    "pairs": [
      [
        "var _nav_marks: Array = []",
        "var cpu_nav_state_provider: RefCounted\nvar _nav_marks: Array = []"
      ],
      [
        "NavSnapshot.build(_nav_layout, String(_context[\"body\"][\"id\"]), observer, _universe_clock.now_s())",
        "NavSnapshot.build(_nav_layout, String(_context[\"body\"][\"id\"]), observer, _universe_clock.now_s(), _navigation_system_states())"
      ]
    ],
    "append": "\n# NAV_CPU3_PROVIDER_V1\nfunc _navigation_system_states() -> Dictionary:\n\tif cpu_nav_state_provider != null:\n\t\treturn cpu_nav_state_provider.call(\"get_states\", _universe_clock.now_s())\n\treturn {}\n"
  },
  {
    "path": "res://game/world/rendering/lk_far_body_snapshot.gd",
    "marker": "SNAPSHOT_CPU3_OPTIONAL_STATES_V1",
    "pairs": [
      [
        "static func build(layout: Dictionary, active_id: String, observer: LkPosition64, epoch_s: float) -> Array[Dictionary]:",
        "static func build(layout: Dictionary, active_id: String, observer: LkPosition64, epoch_s: float, provided_states: Dictionary = {}) -> Array[Dictionary]:"
      ],
      [
        "\tvar states: Dictionary = SafeLayout.evaluate(layout, epoch_s)",
        "\tvar states: Dictionary = provided_states\n\tif not states.is_empty() and (states.get(\"system_id\", \"\") != layout.get(\"system_id\", \"\") or states.get(\"time_s\", NAN) != epoch_s):\n\t\tpush_error(\"FarSnapshot: provided state scope/time mismatch\")\n\t\treturn result\n\tif states.is_empty():\n\t\tstates = SafeLayout.evaluate(layout, epoch_s)"
      ]
    ],
    "append": "\n# SNAPSHOT_CPU3_OPTIONAL_STATES_V1: callers without fifth argument unchanged.\n"
  },
  {
    "path": "res://game/world/rendering/lk_catalog_far_mesh.gd",
    "marker": "FARMESH_CPU3_PROVIDER_V1",
    "pairs": [
      [
        "var _far_layout: Dictionary = {}",
        "var cpu_state_provider: RefCounted\nvar _far_layout: Dictionary = {}"
      ],
      [
        "\tvar records: Array[Dictionary] = FarSnapshot.build(_far_layout, _far_active_id, observer, _far_clock.now_s())",
        "\tvar snapshot_epoch: float = _far_clock.now_s()\n\tvar shared_states: Dictionary = {}\n\tif cpu_state_provider != null:\n\t\tshared_states = cpu_state_provider.call(\"get_states\", snapshot_epoch)\n\tvar records: Array[Dictionary] = FarSnapshot.build(_far_layout, _far_active_id, observer, snapshot_epoch, shared_states)"
      ]
    ],
    "append": "\n# FARMESH_CPU3_PROVIDER_V1: optional exact-epoch provider, null by default.\n"
  }
]

func _initialize() -> void:
	var originals: Dictionary = {}
	var changed: Dictionary = {}
	var already: int = 0
	for spec: Dictionary in EDITS:
		var path: String = spec["path"]
		var source: String = FileAccess.get_file_as_string(path)
		originals[path] = source
		if source.contains(spec["marker"]):
			already += 1
			continue
		for pair: Array in spec["pairs"]:
			if source.count(pair[0]) != 1:
				push_error("FlightCPU3Install: unexpected source " + path + "; no source changed")
				quit(1)
				return
			# Apply sequentially only in memory; validate all files before writing.
			source = source.replace(pair[0], pair[1])
		changed[path] = source + String(spec["append"])
	if already == EDITS.size():
		print("FlightCPU3Install: already installed")
		quit(0)
		return
	if already != 0:
		push_error("FlightCPU3Install: partial prior installation; no sources changed; inspect backups")
		quit(1)
		return
	for path: String in changed:
		var backup: String = path + ".pre_flight_cpu3.bak"
		if not FileAccess.file_exists(backup) and not _write(backup, originals[path]):
			push_error("FlightCPU3Install: backup failed; no sources changed")
			quit(1)
			return
		if not _write(path + ".tmp", changed[path]):
			push_error("FlightCPU3Install: temporary write failed; no sources changed")
			quit(1)
			return
	var committed: Array[String] = []
	for path: String in changed:
		if DirAccess.rename_absolute(path + ".tmp", path) != OK:
			for previous: String in committed:
				if _write(previous + ".rollback.tmp", originals[previous]):
					if DirAccess.rename_absolute(previous + ".rollback.tmp", previous) != OK:
						push_error("FlightCPU3Install: ROLLBACK FAILED " + previous + "; backup retained")
			push_error("FlightCPU3Install: replacement failed " + path + "; rollback attempted, backups retained")
			quit(1)
			return
		committed.append(path)
	print("FlightCPU3Install: APPLIED 4 source hooks; collision cadence unchanged, old providers default null")
	quit(0)

func _write(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error == OK
