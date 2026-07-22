extends Node
## Root scene. Milestone 1: boots straight into the race.
## Later: menu / season shell lives here.

const RACE_SCENE := "res://scenes/race/race.tscn"

var _screenshot_timer := -1.0


func _ready() -> void:
	# Debug hook: `--screenshot` on the command line saves a frame and quits (visual CI).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot"):
			_screenshot_timer = 6.0
	var race: Node = load(RACE_SCENE).instantiate()
	add_child(race)


func _process(delta: float) -> void:
	if _screenshot_timer > 0.0:
		_screenshot_timer -= delta
		if _screenshot_timer <= 0.0:
			var img := get_viewport().get_texture().get_image()
			var out_path := "user://screenshot.png"
			img.save_png(out_path)
			print("SCREENSHOT_SAVED: ", ProjectSettings.globalize_path(out_path))
			get_tree().quit()
