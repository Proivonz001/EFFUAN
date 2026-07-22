class_name MainMenu
extends Control
## Title screen: new career / continue / exhibition race.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "EFFUAN"
	title.add_theme_font_override("font", load("res://assets/fonts/TitilliumWeb-Bold.ttf"))
	title.add_theme_font_size_override("font_size", 84)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var accent := ColorRect.new()
	accent.color = UIKit.ACCENT
	accent.custom_minimum_size = Vector2(340, 4)
	vbox.add_child(accent)

	var subtitle := Label.new()
	subtitle.text = "minimalist racing management"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", UIKit.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	vbox.add_child(_spacer(30))

	_add_button(vbox, "NEW CAREER", func() -> void:
		GameState.new_career()
		_main().goto_hub())

	var cont := _add_button(vbox, "CONTINUE", func() -> void:
		if GameState.load_career():
			_main().goto_hub())
	cont.disabled = not GameState.has_save()

	_add_button(vbox, "EXHIBITION RACE", func() -> void:
		GameState.career_active = false
		GameData.player_team_id = "meteora"
		_main().goto_race())


func _add_button(parent: Node, text: String, handler: Callable) -> Button:
	var b := UIKit.button(text, Vector2(340, 56), 20, handler)
	parent.add_child(b)
	return b


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _main() -> Node:
	return get_node("/root/Main")
