class_name FastestLapBanner
extends PanelContainer
## F1-TV-style purple banner that slides in when the session fastest lap falls.

const SHOW_TIME := 4.5

var manager: RaceManager
var _label: Label
var _timer := 0.0


func _ready() -> void:
	manager = get_node("../..")
	manager.fastest_lap_set.connect(_on_fastest_lap)
	visible = false

	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -230.0
	offset_right = 230.0
	offset_top = 18.0
	offset_bottom = 64.0

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.42, 0.12, 0.55)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.75, 0.4, 0.95)
	sb.set_content_margin_all(10.0)
	add_theme_stylebox_override("panel", sb)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.97, 0.9, 1.0))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)


func _on_fastest_lap(car: CarData, time: float) -> void:
	var m := int(time / 60.0)
	_label.text = "FASTEST LAP   %s   %d:%06.3f" % [car.short_code(), m, time - m * 60.0]
	visible = true
	modulate = Color.WHITE
	_timer = SHOW_TIME
	Sfx.radio()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer < 1.0:
		modulate = Color(1, 1, 1, maxf(_timer, 0.0))
	if _timer <= 0.0:
		visible = false
