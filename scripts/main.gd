extends Node
## Root scene / game-flow state machine:
## MENU -> HUB -> SETUP(+quali) -> RACE -> (results) -> HUB ... -> SEASON END.
## Screens are swapped as single children; each screen navigates via goto_*().

const RACE_SCENE := "res://scenes/race/race.tscn"

var _screen: Node
var _ui_layer: CanvasLayer
var _fade: ColorRect
var _screenshot_timer := -1.0


func _ready() -> void:
	# Control-based screens need a CanvasLayer ancestor to inherit the viewport
	# rect for their anchors (Main itself is a plain Node).
	_ui_layer = CanvasLayer.new()
	add_child(_ui_layer)
	# Fade curtain for screen transitions.
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 90
	add_child(fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.03, 0.035, 0.05)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.modulate = Color(1, 1, 1, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade)
	var start := "menu"
	for arg in OS.get_cmdline_user_args():
		# Debug hooks for automated visual verification.
		if arg.begins_with("--screenshot"):
			_screenshot_timer = 6.0
			if "=" in arg:
				_screenshot_timer = maxf(float(arg.get_slice("=", 1)), 1.0)
		elif arg == "--test-hub":
			start = "hub"
		elif arg == "--test-race":
			start = "race"
		elif arg == "--test-setup":
			start = "setup"
		elif arg == "--test-season":
			start = "season"
	match start:
		"menu":
			goto_menu()
		"hub":
			GameState.new_career()
			goto_hub()
		"setup":
			GameState.new_career()
			goto_setup()
		"race":
			GameState.new_career()
			GameState.pending_weather = GameState.make_weather()
			goto_race()
		"season":
			SeasonRunner.new().run(get_tree())


func goto_menu() -> void:
	_swap(preload("res://scripts/ui/menu.gd").new())


func goto_hub() -> void:
	_swap(preload("res://scripts/ui/hub.gd").new())


func goto_setup() -> void:
	_swap(preload("res://scripts/ui/setup_screen.gd").new())


func goto_race() -> void:
	_swap(load(RACE_SCENE).instantiate())


func goto_season_end() -> void:
	_swap(preload("res://scripts/ui/season_end.gd").new())


func _swap(node: Node) -> void:
	# Quick fade through dark between screens (skipped for the very first one).
	var animate: bool = _screen != null and _fade != null
	if animate:
		var tween_in := create_tween()
		tween_in.tween_property(_fade, "modulate:a", 1.0, 0.14)
		await tween_in.finished
	if _screen:
		_screen.queue_free()
	_screen = node
	if node is Control:
		_ui_layer.add_child(node)
	else:
		add_child(node)
	if animate:
		var tween_out := create_tween()
		tween_out.tween_property(_fade, "modulate:a", 0.0, 0.18)


func _process(delta: float) -> void:
	if _screenshot_timer > 0.0:
		_screenshot_timer -= delta
		if _screenshot_timer <= 0.0:
			var img := get_viewport().get_texture().get_image()
			var out_path := "user://screenshot.png"
			img.save_png(out_path)
			print("SCREENSHOT_SAVED: ", ProjectSettings.globalize_path(out_path))
			get_tree().quit()
