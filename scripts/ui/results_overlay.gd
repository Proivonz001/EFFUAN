class_name ResultsOverlay
extends CenterContainer
## Full-screen classification shown when the race finishes.

var manager: RaceManager


func _ready() -> void:
	manager = get_node("../..")
	manager.race_finished.connect(_on_race_finished)
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_race_finished(classification: Array) -> void:
	visible = true
	var panel := PanelContainer.new()
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "RACE COMPLETE"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var leader: CarData = classification[0]
	var series: SeriesData = GameState.player_series() if GameState.career_active \
			else GameData.get_current_series()
	var scoring := 0
	for i in classification.size():
		var car: CarData = classification[i]
		var pts := 0
		var gap: String
		if car.dnf:
			gap = "DNF"
		else:
			gap = "WINNER" if i == 0 else "+%.1f" % (car.finish_time - leader.finish_time)
			if scoring < series.points_table.size():
				pts = series.points_table[scoring]
			scoring += 1
		var row := Label.new()
		row.text = "P%-3d %s  %-18s %-10s %s pts" % [i + 1, car.short_code(), car.team.team_name, gap, str(pts)]
		row.add_theme_font_size_override("font_size", 15)
		if car.is_player:
			row.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		elif car.dnf:
			row.add_theme_color_override("font_color", Color(0.55, 0.57, 0.62))
		vbox.add_child(row)

	vbox.add_child(HSeparator.new())
	var main := get_node("/root/Main")
	if GameState.career_active:
		vbox.add_child(UIKit.button("CONTINUE", Vector2(220, 48), 16, func() -> void:
			GameState.apply_player_race(classification)
			if GameState.season_over:
				main.goto_season_end()
			else:
				main.goto_hub()))
	else:
		vbox.add_child(UIKit.button("RACE AGAIN", Vector2(200, 48), 16,
				func() -> void: main.goto_race()))
		vbox.add_child(UIKit.button("MENU", Vector2(200, 44), 15,
				func() -> void: main.goto_menu()))
