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
	offset_left = -560.0
	offset_top = -240.0
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
	for i in RaceManager.TIME_SCALES.size():
		var b := _mk_button("%d×" % int(RaceManager.TIME_SCALES[i]), 52)
		b.pressed.connect(func() -> void:
			manager.set_time_scale(i)
			_refresh())
		top.add_child(b)
		_speed_buttons.append(b)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	vbox.add_child(_status)

	# Row: ERS modes.
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

	_status.text = "%s   |   Fuel %.1f kg   ERS %d%%   |   %s  wear %d%%  %d°C%s" % [
		selected.display_name(),
		selected.fuel_kg,
		int(selected.ers_charge),
		selected.compound.display_name,
		int(selected.tyre_wear * 100.0),
		int(selected.tyre_temp_c),
		"   |   IN PIT" if selected.in_pit else "",
	]


func _mk_button(text: String, min_width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 44)
	b.add_theme_font_size_override("font_size", 14)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _set_active(b: Button, active: bool) -> void:
	b.modulate = Color(0.55, 1.0, 0.65) if active else Color.WHITE


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s
