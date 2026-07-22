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
	self_modulate = Color(1, 1, 1, 0.94)
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -988.0
	offset_top = -368.0
	offset_right = -24.0
	offset_bottom = -24.0

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)

	# Session strip.
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 8)
	v.add_child(strip)
	_cam_button = UIKit.button("CAM FULL", Vector2(110, 40), 13, func() -> void:
		manager.cycle_camera()
		_refresh())
	strip.add_child(_cam_button)
	strip.add_child(UIKit.hspacer())
	_pause_button = UIKit.button("❚❚ PAUSE", Vector2(110, 40), 13, func() -> void:
		manager.toggle_pause()
		_refresh())
	strip.add_child(_pause_button)
	for i in RaceManager.TIME_SCALES.size():
		var idx := i
		var b := UIKit.button("%d×" % int(RaceManager.TIME_SCALES[i]), Vector2(52, 40), 13,
				func() -> void:
					manager.set_time_scale(idx)
					_refresh())
		strip.add_child(b)
		_speed_buttons.append(b)

	# The two driver cards.
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	v.add_child(cards)
	for car: CarData in players:
		var card := DriverCard.new()
		cards.add_child(card)
		card.setup(manager, car)
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
