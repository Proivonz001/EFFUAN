class_name SeasonEndScreen
extends Control
## End-of-season review: final tables, promotion/relegation verdicts.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "SEASON %d COMPLETE" % GameState.season
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 30)
	vbox.add_child(columns)
	for sid in ["effuan_one", "effuan_two"]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		columns.add_child(col)
		var head := Label.new()
		head.text = GameData.series[sid].series_name
		head.add_theme_font_size_override("font_size", 16)
		col.add_child(head)
		# Frozen pre-swap tables — the live ones already reflect next season's grids.
		var table: Array = GameState.final_standings.get(sid, [])
		for i in table.size():
			var team: TeamData = GameData.teams[table[i].team_id]
			var row := Label.new()
			row.text = "%2d  %-20s %4d pts" % [i + 1, team.team_name, int(table[i].points)]
			row.add_theme_font_size_override("font_size", 14)
			if team.id == GameState.player_team_id:
				row.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			col.add_child(row)

	vbox.add_child(HSeparator.new())
	for line in GameState.promotion_report:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 15)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if line.begins_with(">>>"):
			l.add_theme_font_size_override("font_size", 18)
			l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		vbox.add_child(l)

	vbox.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)
	var next := UIKit.button("START SEASON %d" % (GameState.season + 1), Vector2(240, 52), 15,
			func() -> void:
				GameState.start_next_season()
				_main().goto_hub())
	buttons.add_child(next)
	var menu := UIKit.button("MAIN MENU", Vector2(160, 52), 15,
			func() -> void: _main().goto_menu())
	buttons.add_child(menu)


func _main() -> Node:
	return get_node("/root/Main")
