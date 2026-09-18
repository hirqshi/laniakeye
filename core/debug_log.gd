class_name DebugLog
extends RefCounted
## Minimal opt-in logger to replace raw print() calls that were scattered
## through player_controller.gd and ship_controller.gd physics code
## (gravity mode switches, jump launches, teleport/runaway detection left
## over from debugging the gravity/jump bugs).
##
## Usage:
##   DebugLog.physics("FLAT JUMP START: v=%s pos=%s" % [v, pos])
##
## Disabled by default. Flip enabled = true (e.g. from an autoload _ready()
## or the debugger) only while actively chasing a physics bug. Always
## no-ops in release exports regardless of the flag.

static var enabled: bool = false


static func physics(message: String) -> void:
	if not enabled:
		return
	if not OS.is_debug_build():
		return
	print(message)
