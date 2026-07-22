class_name RaceLeaderboard
extends PanelContainer
## Live timing tower, broadcast style. Builds its rows in code and refreshes
## on RaceManager.positions_changed (4Hz) — no per-frame UI work.

const ROW_COUNT := 20
const FLASH_TIME := 1.2

var manager: RaceManager

var _lap_label: Label
var _title_label: Label
var _rows: Array = []            # each: {root, pos, bar, code, gap, tyre, wear, delta}
var _flash: Dictionary = {}      # car index -> seconds remaining
var _last_pos: Dictionary = {}   # car index -> last shown position
var _deltas: Dictionary = {}     # car index -> {d: int, t: float}


func _ready() -> void:
	manager = get_node("../..")
	manager.positions_changed.connect(_on_positions)
	manager.leader_lap_changed.connect(_on_leader_lap)
	manager.overtake_happened.connect(_on_overtake)
	manager.fastest_lap_set.connect(_on_fastest_lap)
	_build()


func _build() -> void:
	self_modulate = Color(1, 1, 1, 0.92)
	position = Vector2(24, 24)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)

	_title_label = Label.new()
	var track: TrackData = GameState.current_track() if GameState.career_active \
			else GameData.get_current_track()
	_title_label.text = track.track_name.to_upper()
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	vbox.add_child(_title_label)

	_lap_label = Label.new()
	_lap_label.text = "LAP 1"
	_lap_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_lap_label)

	vbox.add_child(HSeparator.new())

	# Column header keys the tower for first-time readers.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	for col in [["P", 24], ["", 5], ["DRIVER", 48], ["GAP", 78], ["TYRE", 16], ["WEAR", 40]]:
		var h := Label.new()
		h.text = col[0]
		h.custom_minimum_size = Vector2(col[1], 0)
		h.add_theme_font_size_override("font_size", 11)
		h.add_theme_color_override("font_color", Color(0.5, 0.53, 0.6))
		if col[0] == "GAP" or col[0] == "P":
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		header.add_child(h)
	vbox.add_child(header)

	for i in ROW_COUNT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var pos := Label.new()
		pos.text = str(i + 1)
		pos.custom_minimum_size = Vector2(24, 0)
		pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pos.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
		row.add_child(pos)

		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(5, 16)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)

		var code := Label.new()
		code.custom_minimum_size = Vector2(48, 0)
		code.add_theme_font_size_override("font_size", 16)
		row.add_child(code)

		var gap := Label.new()
		gap.custom_minimum_size = Vector2(78, 0)
		gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		gap.add_theme_font_size_override("font_size", 14)
		gap.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
		row.add_child(gap)

		var tyre := Label.new()
		tyre.custom_minimum_size = Vector2(16, 0)
		tyre.add_theme_font_size_override("font_size", 15)
		row.add_child(tyre)

		var wear := Label.new()
		wear.custom_minimum_size = Vector2(40, 0)
		wear.add_theme_font_size_override("font_size", 12)
		wear.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7))
		row.add_child(wear)

		var delta := Label.new()
		delta.custom_minimum_size = Vector2(28, 0)
		delta.add_theme_font_size_override("font_size", 13)
		row.add_child(delta)

		# Last-sector dot: green = personal best, purple = session best.
		var sector := ColorRect.new()
		sector.custom_minimum_size = Vector2(7, 7)
		sector.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sector.color = Color.TRANSPARENT
		row.add_child(sector)

		vbox.add_child(row)
		_rows.append({"root": row, "pos": pos, "bar": bar, "code": code, "gap": gap, "tyre": tyre, "wear": wear, "delta": delta, "sector": sector})


func _process(delta: float) -> void:
	for key in _flash.keys():
		_flash[key] -= delta
		if _flash[key] <= 0.0:
			_flash.erase(key)
	for key in _deltas.keys():
		_deltas[key].t -= delta
		if _deltas[key].t <= 0.0:
			_deltas.erase(key)


func _on_leader_lap(lap: int, total: int) -> void:
	_lap_label.text = "LAP %d / %d" % [lap, total]


func _sync_sc_banner() -> void:
	var engine: RaceEngine = manager.engine
	if engine.sc_active:
		_lap_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		if not _lap_label.text.ends_with("SAFETY CAR"):
			_lap_label.text += "   ⚠ SAFETY CAR"
	else:
		_lap_label.add_theme_color_override("font_color", Color.WHITE)
		_lap_label.text = _lap_label.text.replace("   ⚠ SAFETY CAR", "")


func _on_overtake(attacker: CarData, _defender: CarData) -> void:
	_flash[attacker.index] = FLASH_TIME


var _fl_holder := -1

func _on_fastest_lap(car: CarData, _time: float) -> void:
	_fl_holder = car.index
	_flash[car.index] = FLASH_TIME + 1.0


func _on_positions(order: Array) -> void:
	_sync_sc_banner()
	var leader: CarData = order[0]
	for i in _rows.size():
		var widgets: Dictionary = _rows[i]
		if i >= order.size():
			widgets.root.visible = false
			continue
		var car: CarData = order[i]
		widgets.bar.color = car.team.primary_color
		widgets.code.text = car.short_code()
		widgets.code.add_theme_color_override("font_color",
				Color(1, 1, 1) if car.is_player else Color(0.85, 0.87, 0.92))
		widgets.gap.text = _gap_text(car, leader, i)
		widgets.tyre.text = car.compound.id.substr(0, 1).to_upper()
		widgets.tyre.add_theme_color_override("font_color", car.compound.display_color)
		widgets.wear.text = "%d%%" % int(car.tyre_wear * 100.0)
		# Stint state at a glance: green fresh, amber going off, red at the cliff.
		var wear_col := UIKit.GOOD
		if car.tyre_wear > 0.62:
			wear_col = UIKit.BAD
		elif car.tyre_wear > 0.45:
			wear_col = UIKit.WARN
		widgets.wear.add_theme_color_override("font_color", wear_col)
		var flashing: bool = _flash.has(car.index)
		if car.dnf:
			widgets.gap.text = "OUT"
			widgets.root.modulate = Color(1, 1, 1, 0.35)
		else:
			widgets.root.modulate = Color(0.4, 1.0, 0.5) if flashing else Color.WHITE

		# Position-change marker, shown for a few seconds.
		var pos_now := i + 1
		if _last_pos.has(car.index) and _last_pos[car.index] != pos_now and not car.dnf:
			_deltas[car.index] = {"d": _last_pos[car.index] - pos_now, "t": 4.0}
		_last_pos[car.index] = pos_now
		if _deltas.has(car.index):
			var d: int = _deltas[car.index].d
			widgets.delta.text = ("+%d" % d) if d > 0 else str(d)
			widgets.delta.add_theme_color_override("font_color",
					UIKit.GOOD if d > 0 else UIKit.BAD)
		else:
			widgets.delta.text = ""

		# Sector dot + fastest-lap holder tint.
		match car.last_sector_status:
			2: widgets.sector.color = Color(0.72, 0.35, 0.95)
			1: widgets.sector.color = UIKit.GOOD
			_: widgets.sector.color = Color.TRANSPARENT
		if car.index == _fl_holder:
			widgets.code.add_theme_color_override("font_color", Color(0.82, 0.55, 1.0))


func _gap_text(car: CarData, leader: CarData, pos_index: int) -> String:
	if pos_index == 0:
		return "LEADER"
	if car.in_pit:
		return "IN PIT"
	if car.finished and leader.finished:
		return "+%.1f" % (car.finish_time - leader.finish_time)
	var lap_diff := leader.laps_crossed - car.laps_crossed
	var track: TrackData = manager.engine.track
	var track_len: float = track.total_length_m()
	var dist_gap: float = leader.race_distance_m - car.race_distance_m
	if dist_gap > track_len * 0.9:
		return "+%dL" % maxi(lap_diff, 1)
	# Convert with the average lap speed, not the local segment speed — otherwise
	# gaps jump around as cars move between slow corners and fast straights.
	var ref_lap: float = leader.last_lap_time if leader.last_lap_time > 0.0 else track.base_lap_time
	return "+%.1f" % (dist_gap / (track_len / ref_lap))
