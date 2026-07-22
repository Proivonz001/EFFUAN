class_name WeatherWidget
extends PanelContainer
## Live weather readout in the race HUD: condition, wetness bar, forecast line.

var manager: RaceManager

var _condition: Label
var _forecast: Label
var _wet_bar: ProgressBar
var _timer := 0.0


func _ready() -> void:
	manager = get_node("../..")
	self_modulate = Color(1, 1, 1, 0.92)
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -280.0
	offset_top = 24.0
	offset_right = -24.0

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_condition = Label.new()
	_condition.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_condition)

	var wet_row := HBoxContainer.new()
	wet_row.add_theme_constant_override("separation", 6)
	vbox.add_child(wet_row)
	var wet_label := Label.new()
	wet_label.text = "WET"
	wet_label.add_theme_font_size_override("font_size", 12)
	wet_label.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7))
	wet_row.add_child(wet_label)
	_wet_bar = ProgressBar.new()
	_wet_bar.max_value = 100.0
	_wet_bar.show_percentage = false
	_wet_bar.custom_minimum_size = Vector2(160, 10)
	_wet_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wet_row.add_child(_wet_bar)

	_forecast = Label.new()
	_forecast.add_theme_font_size_override("font_size", 13)
	_forecast.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	vbox.add_child(_forecast)
	_refresh()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		_refresh()


func _refresh() -> void:
	var w: WeatherSystem = manager.engine.weather
	_condition.text = w.condition_text()
	var raining := w.intensity > 0.15
	_condition.add_theme_color_override("font_color",
			Color(0.45, 0.7, 1.0) if raining or w.wetness > 0.3 else Color(1.0, 0.85, 0.4))
	_wet_bar.value = w.wetness * 100.0
	_forecast.text = w.forecast_text(manager.engine.sim_time,
			RaceManager.TIME_SCALES[manager.time_scale_index])
