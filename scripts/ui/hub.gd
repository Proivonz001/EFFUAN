class_name SeasonHub
extends Control
## The out-of-race dashboard: standings, next race card, R&D program.
## Fast navigation, zero menu bloat: one screen, one CONTINUE button.

const PILLARS := ["aero", "power", "chassis", "reliability"]

var _selected_pillar := "aero"
var _selected_variant := 1
var _pillar_buttons := {}
var _variant_buttons: Array = []
var _buy_button: Button
var _xp_label: Label
var _rnd_msg: Label
var _progress_box: VBoxContainer
var _showing_other_series := false
var _standings_box: VBoxContainer
var _toggle_series_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	# ---- header ----
	var header := HBoxContainer.new()
	root.add_child(header)
	var team: TeamData = GameData.teams[GameState.player_team_id]
	var series: SeriesData = GameState.player_series()
	var title := Label.new()
	title.text = "%s   —   %s" % [team.team_name.to_upper(), series.series_name]
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", team.primary_color)
	header.add_child(title)
	header.add_child(_hspacer())
	var season_label := Label.new()
	var total_rounds: int = series.calendar_track_ids.size()
	season_label.text = "SEASON %d   ROUND %d / %d" % [GameState.season,
			mini(GameState.round_index + 1, total_rounds), total_rounds]
	season_label.add_theme_font_size_override("font_size", 20)
	header.add_child(season_label)

	if GameState.last_rnd_report != "":
		var report := Label.new()
		report.text = GameState.last_rnd_report
		report.add_theme_font_size_override("font_size", 14)
		report.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
		root.add_child(report)

	# ---- main columns ----
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	# left: standings
	var left := PanelContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	var left_v := VBoxContainer.new()
	left_v.add_theme_constant_override("separation", 6)
	left.add_child(left_v)
	var st_header := HBoxContainer.new()
	left_v.add_child(st_header)
	var st_title := Label.new()
	st_title.text = "STANDINGS"
	st_title.add_theme_font_size_override("font_size", 18)
	st_header.add_child(st_title)
	st_header.add_child(_hspacer())
	_toggle_series_btn = Button.new()
	_toggle_series_btn.focus_mode = Control.FOCUS_NONE
	_toggle_series_btn.pressed.connect(func() -> void:
		_showing_other_series = not _showing_other_series
		_rebuild_standings())
	st_header.add_child(_toggle_series_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_v.add_child(scroll)
	_standings_box = VBoxContainer.new()
	_standings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_standings_box)
	_rebuild_standings()

	# right: next race + R&D
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	_build_next_race_card(right)
	_build_rnd_panel(right)
	_build_team_card(right)

	# ---- footer ----
	var footer := HBoxContainer.new()
	root.add_child(footer)
	footer.add_child(_hspacer())
	var go := Button.new()
	go.custom_minimum_size = Vector2(320, 56)
	go.add_theme_font_size_override("font_size", 20)
	go.focus_mode = Control.FOCUS_NONE
	if GameState.season_over:
		go.text = "SEASON REVIEW"
		go.pressed.connect(func() -> void: _main().goto_season_end())
	else:
		go.text = "RACE WEEKEND  >"
		go.pressed.connect(func() -> void: _main().goto_setup())
	footer.add_child(go)


func _rebuild_standings() -> void:
	for child in _standings_box.get_children():
		child.queue_free()
	var sid := GameState.player_series_id
	if _showing_other_series:
		sid = "effuan_one" if sid == "effuan_two" else "effuan_two"
	var other_name: String = GameData.series["effuan_one" if sid == "effuan_two" else "effuan_two"].series_name
	_toggle_series_btn.text = "view " + other_name

	var s_label := Label.new()
	s_label.text = GameData.series[sid].series_name
	s_label.add_theme_font_size_override("font_size", 14)
	s_label.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7))
	_standings_box.add_child(s_label)

	var drivers: Array = GameState.driver_standings(sid)
	for i in drivers.size():
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
		bar.color = drivers[i].team.primary_color if drivers[i].team else Color.GRAY
		row.add_child(bar)
		var nm := Label.new()
		nm.text = drivers[i].driver.driver_name
		nm.custom_minimum_size = Vector2(210, 0)
		if drivers[i].team and drivers[i].team.id == GameState.player_team_id:
			nm.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		row.add_child(nm)
		var pts := Label.new()
		pts.text = str(int(drivers[i].points)) + " pts"
		row.add_child(pts)
		_standings_box.add_child(row)

	_standings_box.add_child(HSeparator.new())
	var t_label := Label.new()
	t_label.text = "CONSTRUCTORS"
	t_label.add_theme_font_size_override("font_size", 13)
	t_label.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7))
	_standings_box.add_child(t_label)
	var teams: Array = GameState.team_standings(sid)
	for i in teams.size():
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
		bar.color = teams[i].team.primary_color
		row.add_child(bar)
		var nm := Label.new()
		nm.text = teams[i].team.team_name
		nm.custom_minimum_size = Vector2(210, 0)
		if teams[i].team.id == GameState.player_team_id:
			nm.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		row.add_child(nm)
		var pts := Label.new()
		pts.text = str(int(teams[i].points)) + " pts"
		row.add_child(pts)
		# Promotion/relegation zone markers.
		if GameData.series[sid].tier == 1 and i >= teams.size() - GameState.RELEGATION_SPOTS:
			nm.add_theme_color_override("font_color", Color(0.95, 0.45, 0.4))
		elif GameData.series[sid].tier == 2 and i < GameState.RELEGATION_SPOTS:
			nm.add_theme_color_override("font_color", Color(0.45, 0.9, 0.5))
		_standings_box.add_child(row)


func _build_next_race_card(parent: Node) -> void:
	if GameState.season_over:
		return
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var track := GameState.current_track()
	var head := Label.new()
	head.text = "NEXT RACE"
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7))
	v.add_child(head)
	var name_l := Label.new()
	name_l.text = track.track_name
	name_l.add_theme_font_size_override("font_size", 22)
	v.add_child(name_l)
	var info := Label.new()
	var character := "balanced track"
	if track.df_bias < -0.3:
		character = "power track — low drag rewarded"
	elif track.df_bias > 0.4:
		character = "twisty — high downforce rewarded"
	info.text = "%d laps   |   %s" % [GameState.player_series().race_laps, character]
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
	v.add_child(info)


func _build_rnd_panel(parent: Node) -> void:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	var head_row := HBoxContainer.new()
	v.add_child(head_row)
	var head := Label.new()
	head.text = "R&D — spend XP on upgrades, delivered after N races"
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7))
	head_row.add_child(head)
	head_row.add_child(_hspacer())
	_xp_label = Label.new()
	_xp_label.add_theme_font_size_override("font_size", 18)
	_xp_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65))
	head_row.add_child(_xp_label)

	# Upgrades in delivery.
	_progress_box = VBoxContainer.new()
	v.add_child(_progress_box)

	var bonuses: Dictionary = GameState.rnd_bonuses.get(GameState.player_team_id, {})
	var pillar_row := HBoxContainer.new()
	pillar_row.add_theme_constant_override("separation", 6)
	v.add_child(pillar_row)
	for pillar in PILLARS:
		var b := Button.new()
		if pillar == "reliability":
			b.text = "REL FIX"
		else:
			b.text = "%s  %+.1f" % [pillar.to_upper(), bonuses.get(pillar, 0.0)]
		b.custom_minimum_size = Vector2(120, 46)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			_selected_pillar = pillar
			_sync_rnd())
		pillar_row.add_child(b)
		_pillar_buttons[pillar] = b

	var variant_row := HBoxContainer.new()
	variant_row.add_theme_constant_override("separation", 6)
	v.add_child(variant_row)
	for i in GameState.UPGRADE_VARIANTS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(155, 52)
		b.focus_mode = Control.FOCUS_NONE
		var idx := i
		b.pressed.connect(func() -> void:
			_selected_variant = idx
			_sync_rnd())
		variant_row.add_child(b)
		_variant_buttons.append(b)
	_buy_button = Button.new()
	_buy_button.text = "BUY"
	_buy_button.custom_minimum_size = Vector2(90, 52)
	_buy_button.add_theme_font_size_override("font_size", 17)
	_buy_button.focus_mode = Control.FOCUS_NONE
	_buy_button.pressed.connect(_on_buy)
	variant_row.add_child(_buy_button)

	_rnd_msg = Label.new()
	_rnd_msg.add_theme_font_size_override("font_size", 13)
	_rnd_msg.add_theme_color_override("font_color", Color(0.95, 0.6, 0.4))
	v.add_child(_rnd_msg)
	_sync_rnd()


func _selected_variant_data() -> Dictionary:
	if _selected_pillar == "reliability":
		return GameState.RELIABILITY_FIX
	return GameState.UPGRADE_VARIANTS[_selected_variant]


func _on_buy() -> void:
	var err: String = GameState.purchase_upgrade(_selected_pillar, _selected_variant_data())
	_rnd_msg.text = err if err != "" else "Ordered — engineers are on it."
	_sync_rnd()


func _sync_rnd() -> void:
	_xp_label.text = "%d XP" % GameState.dev_points
	for pillar in _pillar_buttons:
		_pillar_buttons[pillar].modulate = \
				Color(0.55, 1.0, 0.65) if pillar == _selected_pillar else Color.WHITE
	var rel_mode: bool = _selected_pillar == "reliability"
	for i in _variant_buttons.size():
		var b: Button = _variant_buttons[i]
		if rel_mode:
			b.visible = i == 0
			var fix: Dictionary = GameState.RELIABILITY_FIX
			b.text = "rel %+.1f\n%d XP · %d race" % [fix.rel, int(fix.cost), int(fix.races)]
			b.modulate = Color(0.55, 1.0, 0.65)
		else:
			b.visible = true
			var vr: Dictionary = GameState.UPGRADE_VARIANTS[i]
			b.text = "%s\n%+.1f stat, rel %+.1f\n%d XP · %d races" % [
					vr.name, vr.gain, vr.rel, int(vr.cost), int(vr.races)]
			b.modulate = Color(0.55, 1.0, 0.65) if i == _selected_variant else Color.WHITE
	var variant := _selected_variant_data()
	_buy_button.disabled = GameState.dev_points < int(variant.cost) \
			or GameState.active_upgrades.size() >= GameState.MAX_ACTIVE_UPGRADES

	for child in _progress_box.get_children():
		child.queue_free()
	for up in GameState.active_upgrades:
		var row := Label.new()
		var races_left := int(up.races_left)
		row.text = "IN PROGRESS: %s %s — ready in %d race%s" % [
				up.name, str(up.pillar).to_upper(), races_left, "" if races_left == 1 else "s"]
		row.add_theme_font_size_override("font_size", 13)
		row.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
		_progress_box.add_child(row)


func _build_team_card(parent: Node) -> void:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var eff: TeamData = GameState.effective_team(GameState.player_team_id)
	var head := Label.new()
	head.text = "CAR   aero %d   power %d   chassis %d   reliability %d" % [
			int(eff.stat_aero), int(eff.stat_power), int(eff.stat_chassis), int(eff.stat_reliability)]
	head.add_theme_font_size_override("font_size", 15)
	v.add_child(head)
	for did in eff.driver_ids:
		var d: DriverData = GameData.drivers[did]
		var row := Label.new()
		row.text = "%s  —  pace %d   confidence %d" % [
				d.driver_name, int(d.skill_pace), int(GameState.confidence.get(did, 50.0))]
		row.add_theme_font_size_override("font_size", 14)
		row.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
		v.add_child(row)


func _hspacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


func _main() -> Node:
	return get_node("/root/Main")
