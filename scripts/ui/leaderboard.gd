class_name RaceLeaderboard
extends PanelContainer
## Live timing tower, broadcast style. Builds its rows in code and refreshes
## on RaceManager.positions_changed (4Hz) — no per-frame UI work.

const ROW_COUNT := 20
const FLASH_TIME := 1.2

var manager: RaceManager

var _lap_label: Label
var _title_label: Label
var _rows: Array = []            # each: {root, pos, bar, code, gap, tyre, wear}
var _flash: Dictionary = {}      # car index -> seconds remaining


func _ready() -> void:
	manager = get_node("../..")
	manager.positions_changed.connect(_on_positions)
	manager.leader_lap_changed.connect(_on_leader_lap)
	manager.overtake_happened.connect(_on_overtake)
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

		vbox.add_child(row)
		_rows.append({"root": row, "pos": pos, "bar": bar, "code": code, "gap": gap, "tyre": tyre, "wear": wear})


func _process(delta: float) -> void:
	for key in _flash.keys():
		_flash[key] -= delta
		if _flash[key] <= 0.0:
			_flash.erase(key)


func _on_leader_lap(lap: int, total: int) -> void:
	_lap_label.text = "LAP %d / %d" % [lap, total]


func _on_overtake(attacker: CarData, _defender: CarData) -> void:
	_flash[attacker.index] = FLASH_TIME


func _on_positions(order: Array) -> void:
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
		var flashing: bool = _flash.has(car.index)
		if car.dnf:
			widgets.gap.text = "OUT"
			widgets.root.modulate = Color(1, 1, 1, 0.35)
		else:
			widgets.root.modulate = Color(0.4, 1.0, 0.5) if flashing else Color.WHITE


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
