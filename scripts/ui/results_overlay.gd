class_name ResultsOverlay
extends CenterContainer
## Full-screen classification shown when the race finishes.

var manager: RaceManager


func _ready() -> void:
	manager = get_node("../..")
	manager.race_finished.connect(_on_race_finished)
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)


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
	var series: SeriesData = GameData.get_current_series()
	for i in classification.size():
		var car: CarData = classification[i]
		var pts: int = series.points_table[i] if i < series.points_table.size() else 0
		var row := Label.new()
		var gap := "WINNER" if i == 0 else "+%.1f" % (car.finish_time - leader.finish_time)
		row.text = "P%-3d %s  %-18s %-10s %s pts" % [i + 1, car.short_code(), car.team.team_name, gap, str(pts)]
		row.add_theme_font_size_override("font_size", 15)
		if car.is_player:
			row.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		vbox.add_child(row)

	vbox.add_child(HSeparator.new())
	var again := Button.new()
	again.text = "RACE AGAIN"
	again.custom_minimum_size = Vector2(200, 48)
	again.pressed.connect(func() -> void:
		get_tree().reload_current_scene())
	vbox.add_child(again)
