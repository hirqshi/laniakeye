class_name SaveSystemRow
extends Control

signal load_requested(seed_value: int)
signal delete_requested(seed_value: int)

@export var seed_label: Label
@export var date_label: Label
@export var load_button: Button
@export var delete_button: Button

var _seed_value: int = 0

func _ready() -> void:
	if load_button != null:
		load_button.pressed.connect(_on_load_button_pressed)

	if delete_button != null:
		delete_button.pressed.connect(_on_delete_button_pressed)

func setup(entry: Dictionary) -> void:
	_seed_value = int(entry.get("seed", 0))

	if seed_label != null:
		seed_label.text = "SEED: %d" % _seed_value

	if date_label != null:
		var timestamp: int = int(entry.get("timestamp", 0))
		date_label.text = _format_timestamp(timestamp)

func _on_load_button_pressed() -> void:
	if _seed_value != 0:
		load_requested.emit(_seed_value)

func _on_delete_button_pressed() -> void:
	if _seed_value != 0:
		delete_requested.emit(_seed_value)

func _format_timestamp(timestamp: int) -> String:
	if timestamp <= 0:
		return "Saved: unknown date"

	var date_time: Dictionary = Time.get_datetime_dict_from_unix_time(timestamp)
	return "Saved: %04d-%02d-%02d %02d:%02d" % [
		int(date_time.get("year", 0)),
		int(date_time.get("month", 0)),
		int(date_time.get("day", 0)),
		int(date_time.get("hour", 0)),
		int(date_time.get("minute", 0)),
	]
