class_name SetupScreen
extends Control
## Pre-race: one downforce slider (the minimalist "practice session"),
## weather outlook, instant qualifying, then straight to the race.

var _slider: HSlider
var _quali_box: VBoxContainer
var _start_btn: Button
var _quali_btn: Button
var _engineer: Label
var _setup_value: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The weekend's weather is rolled once here and shared by quali + race.
	if GameState.pending_weather == null:
		GameState.pending_weather = GameState.make_weather()

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 24)
	margin.add_child(root)

	# ---- left column: race info + setup ----
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	left.custom_minimum_size = Vector2(560, 0)
	root.add_child(left)

	var track := GameState.current_track()
	var series := GameState.player_series()
	var title := Label.new()
	title.text = track.track_name
	title.add_theme_font_size_override("font_size", 34)
	left.add_child(title)
	var sub := Label.new()
	sub.text = "%s   |   Round %d   |   %d laps" % [series.series_name,
			GameState.round_index + 1, series.race_laps]
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	left.add_child(sub)

	var weather := Label.new()
	weather.text = "Forecast: " + GameState.pending_weather.preview_text()
	weather.add_theme_font_size_override("font_size", 16)
	weather.add_theme_color_override("font_color", Color(0.45, 0.7, 1.0))
	left.add_child(weather)

	left.add_child(HSeparator.new())

	var setup_head := Label.new()
	setup_head.text = "CAR SETUP"
	setup_head.add_theme_font_size_override("font_size", 18)
	left.add_child(setup_head)

	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 10)
	left.add_child(slider_row)
	var lo := Label.new()
	lo.text = "LOW DRAG\n-1.0"
	lo.add_theme_font_size_override("font_size", 13)
	slider_row.add_child(lo)
	_slider = HSlider.new()
	_slider.min_value = -1.0
	_slider.max_value = 1.0
	_slider.step = 0.05
	_slider.value = GameState.pending_setup_bias
	_slider.tick_count = 9
	_slider.ticks_on_borders = true
	_slider.custom_minimum_size = Vector2(340, 36)
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(func(_v: float) -> void: _update_setup_readout())
	slider_row.add_child(_slider)
	var hi := Label.new()
	hi.text = "HIGH DOWNFORCE\n+1.0"
	hi.add_theme_font_size_override("font_size", 13)
	slider_row.add_child(hi)

	_setup_value = Label.new()
	_setup_value.add_theme_font_size_override("font_size", 16)
	left.add_child(_setup_value)

	_engineer = Label.new()
	_engineer.add_theme_font_size_override("font_size", 14)
	_engineer.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
	var hint := "The engineers expect a balanced setup to work here."
	if track.df_bias < -0.3:
		hint = "Engineer: long straights — trim the wing, protect top speed."
	elif track.df_bias > 0.4:
		hint = "Engineer: it's all corners out there — load up on downforce."
	_engineer.text = hint
	left.add_child(_engineer)
	_update_setup_readout()

	# Driver confidence card.
	var team: TeamData = GameData.teams[GameState.player_team_id]
	for did in team.driver_ids:
		var d: DriverData = GameData.drivers[did]
		var row := Label.new()
		row.text = "%s (%s)  —  confidence %d" % [d.driver_name, d.code,
				int(GameState.confidence.get(did, 50.0))]
		row.add_theme_font_size_override("font_size", 14)
		row.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
		left.add_child(row)

	left.add_child(_vspacer())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	left.add_child(buttons)
	var back := UIKit.button("< BACK", Vector2(120, 52), 14,
			func() -> void: _main().goto_hub())
	buttons.add_child(back)
	_quali_btn = UIKit.button("QUALIFY", Vector2(220, 52), 18, _on_qualify)
	buttons.add_child(_quali_btn)
	_start_btn = UIKit.button("START RACE  >", Vector2(220, 52), 18,
			func() -> void: _main().goto_race())
	_start_btn.visible = false
	buttons.add_child(_start_btn)

	# ---- right column: quali classification ----
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var right_v := VBoxContainer.new()
	right.add_child(right_v)
	var q_head := Label.new()
	q_head.text = "QUALIFYING"
	q_head.add_theme_font_size_override("font_size", 18)
	right_v.add_child(q_head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_v.add_child(scroll)
	_quali_box = VBoxContainer.new()
	_quali_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_quali_box)
	var placeholder := Label.new()
	placeholder.text = "Set your car up, then send the drivers out."
	placeholder.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7))
	_quali_box.add_child(placeholder)


func _on_qualify() -> void:
	GameState.pending_setup_bias = _slider.value
	var entries: Array = GameState.build_entries(GameState.player_series_id)
	var sorted: Array = GameState.run_qualifying(entries)
	GameState.pending_grid = sorted

	for child in _quali_box.get_children():
		child.queue_free()
	var pole_time: float = sorted[0].quali_time
	for i in sorted.size():
		var e: Dictionary = sorted[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var pos := Label.new()
		pos.text = str(i + 1)
		pos.custom_minimum_size = Vector2(26, 0)
		pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pos.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7))
		row.add_child(pos)
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(5, 15)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.color = e.team.primary_color
		row.add_child(bar)
		var nm := Label.new()
		nm.text = "%s  %s" % [e.driver.code, e.driver.driver_name]
		nm.custom_minimum_size = Vector2(240, 0)
		if e.team.id == GameState.player_team_id:
			nm.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		row.add_child(nm)
		var tm := Label.new()
		tm.text = "%.3f" % e.quali_time if i == 0 else "+%.3f" % (e.quali_time - pole_time)
		row.add_child(tm)
		_quali_box.add_child(row)

	_quali_btn.disabled = true
	_slider.editable = false
	_start_btn.visible = true


func _update_setup_readout() -> void:
	if _setup_value == null:
		return
	var v: float = _slider.value
	var zone := "balanced"
	if v <= -0.6:
		zone = "very low drag"
	elif v <= -0.2:
		zone = "low drag"
	elif v >= 0.6:
		zone = "maximum downforce"
	elif v >= 0.2:
		zone = "high downforce"
	_setup_value.text = "Setting: %+.2f  (%s)   —   corners %s, straights %s" % [
		v, zone,
		"faster" if v > 0.05 else ("slower" if v < -0.05 else "neutral"),
		"slower" if v > 0.05 else ("faster" if v < -0.05 else "neutral"),
	]


func _vspacer() -> Control:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


func _main() -> Node:
	return get_node("/root/Main")
