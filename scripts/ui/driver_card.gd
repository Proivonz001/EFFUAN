class_name DriverCard
extends PanelContainer
## One pit-wall card per player driver: vector-drawn battery / tyre / fuel
## gauges, three ERS modes and the OVERTAKE boost (armed only when the car was
## within 1s at the detection point on the previous lap).

const REFRESH_INTERVAL := 0.2
const MODE_NAMES := ["HARVEST", "NEUTRAL", "DEPLOY"]
const MODE_COLORS := [Color(0.42, 0.92, 0.55), Color(0.62, 0.68, 0.78), Color(1.0, 0.35, 0.9)]
const OVT_COLOR := Color(1.0, 0.72, 0.15)

var manager: RaceManager
var car: CarData

var _gauges: Control
var _gaps: Label
var _pos_label: Label
var _pit_proj: Label
var _mode_buttons: Array = []
var _ovt_button: Button
var _compound_buttons: Array = []
var _box_button: Button
var _pit_compound: TyreCompound
var _timer := 0.0
var _font: Font


func setup(p_manager: RaceManager, p_car: CarData) -> void:
	manager = p_manager
	car = p_car
	_pit_compound = GameData.get_compound("medium")
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(462, 0)
	_build()
	_refresh()


func _build() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)

	# Header: color bar + code + name + live gaps.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	_pos_label = UIKit.label("P–", 22, UIKit.TEXT)
	_pos_label.custom_minimum_size = Vector2(44, 0)
	head.add_child(_pos_label)
	head.add_child(UIKit.team_bar(car.team.primary_color, 20))
	var code := UIKit.label(car.short_code(), 20, UIKit.GOLD)
	head.add_child(code)
	head.add_child(UIKit.label(car.display_name(), 14, UIKit.TEXT_DIM))
	head.add_child(UIKit.hspacer())
	_gaps = UIKit.label("", 12, UIKit.TEXT_DIM)
	head.add_child(_gaps)

	# Vector gauge strip (battery / tyre / fuel).
	_gauges = Control.new()
	_gauges.custom_minimum_size = Vector2(0, 92)
	_gauges.draw.connect(_draw_gauges)
	v.add_child(_gauges)

	# ERS modes + boost.
	var ers_row := HBoxContainer.new()
	ers_row.add_theme_constant_override("separation", 5)
	v.add_child(ers_row)
	for i in MODE_NAMES.size():
		var mode := i
		var b := UIKit.button(MODE_NAMES[i], Vector2(92, 42), 12, func() -> void:
			manager.cmd_set_ers(car, mode)
			_refresh())
		ers_row.add_child(b)
		_mode_buttons.append(b)
	_ovt_button = UIKit.button("OVERTAKE", Vector2(140, 42), 13, func() -> void:
		manager.cmd_set_ers(car, CarData.ErsMode.OVERTAKE)
		_refresh())
	ers_row.add_child(_ovt_button)

	# Pit call.
	var pit_row := HBoxContainer.new()
	pit_row.add_theme_constant_override("separation", 5)
	v.add_child(pit_row)
	pit_row.add_child(UIKit.label("PIT", 11, UIKit.TEXT_FAINT))
	for cid in ["soft", "medium", "hard", "inter", "wet"]:
		var compound := GameData.get_compound(cid)
		if compound == null:
			continue
		var b := UIKit.button(cid.substr(0, 1).to_upper(), Vector2(40, 38), 13, Callable())
		b.add_theme_color_override("font_color", compound.display_color)
		b.pressed.connect(func() -> void:
			_pit_compound = compound
			_refresh())
		pit_row.add_child(b)
		_compound_buttons.append({"b": b, "c": compound})
	pit_row.add_child(UIKit.hspacer())
	_pit_proj = UIKit.label("", 12, UIKit.TEXT_DIM)
	pit_row.add_child(_pit_proj)
	_box_button = UIKit.button("BOX", Vector2(86, 38), 14, func() -> void:
		manager.cmd_toggle_pit(car, _pit_compound)
		_refresh())
	pit_row.add_child(_box_button)


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= REFRESH_INTERVAL:
		_timer = 0.0
		_refresh()


func _refresh() -> void:
	if car == null:
		return
	_gauges.queue_redraw()
	for i in _mode_buttons.size():
		UIKit.set_active(_mode_buttons[i], int(car.ers_mode) == i)
	var ovt_active: bool = car.ers_mode == CarData.ErsMode.OVERTAKE
	_ovt_button.disabled = not car.overtake_available and not ovt_active
	if ovt_active:
		_ovt_button.text = "OVERTAKE ⚡"
		_ovt_button.modulate = OVT_COLOR
	elif car.overtake_available:
		_ovt_button.text = "OVERTAKE ✓"
		_ovt_button.modulate = Color(1.0, 0.9, 0.6)
	else:
		_ovt_button.text = "OVERTAKE"
		_ovt_button.modulate = Color.WHITE
	for entry in _compound_buttons:
		UIKit.set_active(entry.b, entry.c == _pit_compound)
	UIKit.set_active(_box_button, car.pit_requested)
	_box_button.text = "BOX ✓" if car.pit_requested else "BOX"

	# Live position + pit rejoin projection.
	var pos_idx: int = manager.engine.order.find(car)
	_pos_label.text = "P%d" % (pos_idx + 1) if pos_idx >= 0 else "P–"
	if car.in_pit or car.dnf or car.finished:
		_pit_proj.text = ""
	else:
		_pit_proj.text = "BOX now → ~P%d" % manager.pit_projection(car)

	var gaps: Array = manager.gaps_around(car)
	var ahead: String = "—" if gaps[0] < 0.0 or gaps[0] > 90.0 else "%.1fs" % gaps[0]
	var behind: String = "—" if gaps[1] < 0.0 or gaps[1] > 90.0 else "%.1fs" % gaps[1]
	var state := ""
	if car.in_pit:
		state = "IN PIT   "
	elif car.dnf:
		state = "OUT   "
	_gaps.text = "%s▲ %s   ▼ %s" % [state, ahead, behind]


# ------------------------------------------------------------ vector gauges --

func _draw_gauges() -> void:
	var mode_col: Color = OVT_COLOR if car.ers_mode == CarData.ErsMode.OVERTAKE \
			else MODE_COLORS[mini(int(car.ers_mode), 2)]

	# --- battery: segmented bar ---
	_gauges.draw_string(_font, Vector2(0, 14), "ERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.TEXT_FAINT)
	var segs := 12
	var filled := int(ceil(car.ers_charge / 100.0 * segs))
	for i in segs:
		var r := Rect2(2 + i * 21.0, 20.0, 17.0, 15.0)
		if i < filled:
			_gauges.draw_rect(r, mode_col)
		else:
			_gauges.draw_rect(r, Color(0.16, 0.175, 0.21))
			_gauges.draw_rect(r, Color(0.25, 0.27, 0.32), false, 1.0)
	_gauges.draw_string(_font, Vector2(260, 33), "%d%%" % int(car.ers_charge),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.TEXT)

	# --- fuel: thin bar under the battery ---
	_gauges.draw_string(_font, Vector2(0, 56), "FUEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.TEXT_FAINT)
	var full: float = manager.engine.race_laps * RaceEngine.BASE_FUEL_BURN_LAP \
			* RaceEngine.MIX_BURN[car.fuel_mix] * RaceEngine.FUEL_LOAD_MARGIN
	var frac: float = clampf(car.fuel_kg / maxf(full, 0.001), 0.0, 1.0)
	_gauges.draw_rect(Rect2(2, 62, 250, 8), Color(0.16, 0.175, 0.21))
	_gauges.draw_rect(Rect2(2, 62, 250 * frac, 8), UIKit.INFO if frac > 0.12 else UIKit.BAD)
	var mix_names := ["LEAN", "STD", "RICH"]
	_gauges.draw_string(_font, Vector2(260, 71), "%.1f kg · %s" % [car.fuel_kg, mix_names[car.fuel_mix]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.TEXT_DIM)

	# --- tyre: wear ring + temperature core ---
	var center := Vector2(392, 39)
	var radius := 26.0
	_gauges.draw_arc(center, radius, 0, TAU, 40, Color(0.16, 0.175, 0.21), 7.0, true)
	var remaining := 1.0 - car.tyre_wear
	if remaining > 0.01:
		var col: Color = car.compound.display_color
		if car.tyre_wear > 0.62:
			col = UIKit.BAD
		elif car.tyre_wear > 0.48:
			col = UIKit.WARN
		_gauges.draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * remaining, 40, col, 7.0, true)
	# temperature core: blue = cold, green = in window, red = overheating
	var opt: float = car.compound.optimal_temp_c
	var t_col := UIKit.GOOD
	if car.tyre_temp_c < opt - car.compound.temp_window_c:
		t_col = Color(0.4, 0.65, 1.0)
	elif car.tyre_temp_c > opt + 8.0:
		t_col = UIKit.BAD
	elif car.tyre_temp_c > opt + 3.0:
		t_col = UIKit.WARN
	_gauges.draw_circle(center, 14.0, Color(t_col, 0.25))
	_gauges.draw_circle(center, 9.0, t_col)
	_gauges.draw_string(_font, center + Vector2(-radius - 4, radius + 16),
			"%s %d%%  %d°C" % [car.compound.id.substr(0, 1).to_upper(),
			int(car.tyre_wear * 100.0), int(car.tyre_temp_c)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.TEXT_DIM)
