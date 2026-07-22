class_name PitWallPanel
extends PanelContainer
## Pit wall: one DriverCard per player driver (both always visible) plus the
## session controls strip (camera, pause, time scale). Fuel mix and starting
## tyres are pre-race commitments — they are set on the setup screen, not here.

const REFRESH_INTERVAL := 0.25

var manager: RaceManager

var _pause_button: Button
var _cam_button: Button
var _speed_buttons: Array = []
var _timer := 0.0


func _ready() -> void:
	manager = get_node("../..")
	var players: Array = manager.player_cars()
	if players.is_empty():
		visible = false
		return
	# Full-width telemetry bar along the bottom: the camera reserves this space
	# (RaceManager.USABLE_RECT), so the HUD never covers the circuit.
	self_modulate = Color(1, 1, 1, 0.96)
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 12.0
	offset_top = -264.0
	offset_right = -12.0
	offset_bottom = -10.0

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	# Left slot stays clear: the radio feed floats there.
	var radio_slot := Control.new()
	radio_slot.custom_minimum_size = Vector2(400, 0)
	row.add_child(radio_slot)

	for car: CarData in players:
		var card := DriverCard.new()
		row.add_child(card)
		card.setup(manager, car)

	row.add_child(UIKit.hspacer())

	# Session strip, vertical at the far right.
	var strip := VBoxContainer.new()
	strip.add_theme_constant_override("separation", 6)
	row.add_child(strip)
	_cam_button = UIKit.button("CAM FULL", Vector2(150, 42), 13, func() -> void:
		manager.cycle_camera()
		_refresh())
	strip.add_child(_cam_button)
	_pause_button = UIKit.button("❚❚ PAUSE", Vector2(150, 42), 13, func() -> void:
		manager.toggle_pause()
		_refresh())
	strip.add_child(_pause_button)
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 4)
	strip.add_child(speeds)
	for i in RaceManager.TIME_SCALES.size():
		var idx := i
		var b := UIKit.button("%d×" % int(RaceManager.TIME_SCALES[i]), Vector2(47, 40), 13,
				func() -> void:
					manager.set_time_scale(idx)
					_refresh())
		speeds.add_child(b)
		_speed_buttons.append(b)
	_refresh()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= REFRESH_INTERVAL:
		_timer = 0.0
		_refresh()


func _refresh() -> void:
	if manager == null:
		return
	for i in _speed_buttons.size():
		UIKit.set_active(_speed_buttons[i], manager.time_scale_index == i)
	_pause_button.text = "▶ RESUME" if manager.paused else "❚❚ PAUSE"
	UIKit.set_active(_pause_button, manager.paused)
	_cam_button.text = "CAM " + RaceManager.CAMERA_MODES[manager.camera_mode]
	UIKit.set_active(_cam_button, manager.camera_mode != 0)
