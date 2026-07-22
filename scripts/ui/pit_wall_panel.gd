class_name PitWallPanel
extends PanelContainer
## Player pit wall: select one of the two team cars, set ERS mode and fuel mix,
## pick the next compound, call the box. Big touch-friendly buttons (mobile-ready
## rule: no hover-critical interaction, min 44px targets).

const ERS_NAMES := ["HARVEST", "NEUTRAL", "DEPLOY", "OVERTAKE"]
const MIX_NAMES := ["LEAN", "STD", "RICH"]
const REFRESH_INTERVAL := 0.25

var manager: RaceManager
var selected: CarData

var _car_buttons: Array = []
var _ers_buttons: Array = []
var _mix_buttons: Array = []
var _compound_buttons: Array = []
var _box_button: Button
var _speed_buttons: Array = []
var _status: Label
var _timer := 0.0
var _pit_compound: TyreCompound
var _pause_button: Button
var _cam_button: Button
var _gaps_label: Label


func _ready() -> void:
	manager = get_node("../..")
	var players: Array = manager.player_cars()
	if players.is_empty():
		visible = false
		return
	selected = players[0]
	_pit_compound = GameData.get_compound("medium")
	_build(players)
	_refresh()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= REFRESH_INTERVAL:
		_timer = 0.0
		_refresh()


func _build(players: Array) -> void:
	self_modulate = Color(1, 1, 1, 0.92)
	# Bottom-right anchor, sized for touch.
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -600.0
	offset_top = -330.0
	offset_right = -24.0
	offset_bottom = -24.0

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	# Row: car selector + time scale.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vbox.add_child(top)
	for car in players:
		var b := _mk_button(car.short_code(), 70)
		b.pressed.connect(func() -> void:
			selected = car
			_refresh())
		top.add_child(b)
		_car_buttons.append(b)
	top.add_child(_spacer())
	_cam_button = _mk_button("CAM FULL", 96)
	_cam_button.pressed.connect(func() -> void:
		manager.cycle_camera()
		_refresh())
	top.add_child(_cam_button)
	_pause_button = _mk_button("❚❚ PAUSE", 100)
	_pause_button.pressed.connect(func() -> void:
		manager.toggle_pause()
		_refresh())
	top.add_child(_pause_button)
	for i in RaceManager.TIME_SCALES.size():
		var b := _mk_button("%d×" % int(RaceManager.TIME_SCALES[i]), 52)
		b.pressed.connect(func() -> void:
			manager.set_time_scale(i)
			_refresh())
		top.add_child(b)
		_speed_buttons.append(b)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(0.88, 0.90, 0.95))
	vbox.add_child(_status)

	_gaps_label = Label.new()
	_gaps_label.add_theme_font_size_override("font_size", 13)
	_gaps_label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	vbox.add_child(_gaps_label)

	# Row: ERS modes.
	vbox.add_child(_section_label("ERS MODE"))
	var ers_row := HBoxContainer.new()
	ers_row.add_theme_constant_override("separation", 6)
	vbox.add_child(ers_row)
	for i in ERS_NAMES.size():
		var b := _mk_button(ERS_NAMES[i], 100)
		b.pressed.connect(func() -> void:
			manager.cmd_set_ers(selected, i)
			_refresh())
		ers_row.add_child(b)
		_ers_buttons.append(b)

	# Row: fuel mix + compound pick + box call.
	var labels_row := HBoxContainer.new()
	vbox.add_child(labels_row)
	labels_row.add_child(_section_label("FUEL MIX"))
	labels_row.add_child(_spacer())
	labels_row.add_child(_section_label("PIT STOP — next tyres + BOX"))
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	vbox.add_child(bottom)
	for i in MIX_NAMES.size():
		var b := _mk_button(MIX_NAMES[i], 64)
		b.pressed.connect(func() -> void:
			manager.cmd_set_mix(selected, i)
			_refresh())
		bottom.add_child(b)
		_mix_buttons.append(b)
	bottom.add_child(_spacer())
	for cid in ["soft", "medium", "hard", "inter", "wet"]:
		var compound := GameData.get_compound(cid)
		if compound == null:
			continue
		var b := _mk_button(cid.substr(0, 1).to_upper(), 44)
		b.add_theme_color_override("font_color", compound.display_color)
		b.pressed.connect(func() -> void:
			_pit_compound = compound
			_refresh())
		bottom.add_child(b)
		_compound_buttons.append({"button": b, "compound": compound})
	_box_button = _mk_button("BOX", 84)
	_box_button.pressed.connect(func() -> void:
		manager.cmd_toggle_pit(selected, _pit_compound)
		_refresh())
	bottom.add_child(_box_button)


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	return l


func _refresh() -> void:
	if selected == null:
		return
	var players: Array = manager.player_cars()
	for i in _car_buttons.size():
		_set_active(_car_buttons[i], players[i] == selected)
	for i in _speed_buttons.size():
		_set_active(_speed_buttons[i], manager.time_scale_index == i)
	for i in _ers_buttons.size():
		_set_active(_ers_buttons[i], selected.ers_mode == i)
	for i in _mix_buttons.size():
		_set_active(_mix_buttons[i], selected.fuel_mix == i)
	for entry in _compound_buttons:
		_set_active(entry.button, entry.compound == _pit_compound)
	_set_active(_box_button, selected.pit_requested)
	_box_button.text = "BOX ✓" if selected.pit_requested else "BOX"
	_pause_button.text = "▶ RESUME" if manager.paused else "❚❚ PAUSE"
	_set_active(_pause_button, manager.paused)
	_cam_button.text = "CAM " + RaceManager.CAMERA_MODES[manager.camera_mode]
	_set_active(_cam_button, manager.camera_mode != 0)

	_status.text = "%s   |   Fuel %.1f kg   ERS %d%%   |   %s  wear %d%%  %d°C%s" % [
		selected.display_name(),
		selected.fuel_kg,
		int(selected.ers_charge),
		selected.compound.display_name,
		int(selected.tyre_wear * 100.0),
		int(selected.tyre_temp_c),
		"   |   IN PIT" if selected.in_pit else "",
	]
	var gaps: Array = manager.gaps_around(selected)
	var ahead_txt: String = "—" if gaps[0] < 0.0 or gaps[0] > 90.0 else "%.1fs" % gaps[0]
	var behind_txt: String = "—" if gaps[1] < 0.0 or gaps[1] > 90.0 else "%.1fs" % gaps[1]
	_gaps_label.text = "gap ahead %s   ·   gap behind %s" % [ahead_txt, behind_txt]


func _mk_button(text: String, min_width: float) -> Button:
	return UIKit.button(text, Vector2(min_width, 44), 14)


func _set_active(b: Button, active: bool) -> void:
	UIKit.set_active(b, active)


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s
