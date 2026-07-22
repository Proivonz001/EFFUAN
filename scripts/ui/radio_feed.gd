class_name RadioFeed
extends VBoxContainer
## Race engineer radio: contextual messages for the player's cars plus race
## events (SC, retirements). Newest at the bottom, auto-fading. Cooldowns per
## message type keep it from spamming.

const MAX_MESSAGES := 5
const MESSAGE_LIFETIME := 7.0
const POLL_INTERVAL := 1.0

const COL_NEUTRAL := Color(0.85, 0.87, 0.92)
const COL_WARN := Color(1.0, 0.75, 0.35)
const COL_GOOD := Color(0.5, 1.0, 0.6)
const COL_SC := Color(1.0, 0.9, 0.2)
const COL_BAD := Color(1.0, 0.45, 0.4)

var manager: RaceManager

var _poll_timer := 0.0
var _cooldowns := {}       # key -> sim_time when it may fire again
var _last_forecast := ""


func _ready() -> void:
	manager = get_node("../..")
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 24.0
	offset_top = -330.0
	offset_bottom = -24.0
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 4)

	manager.pit_event.connect(_on_pit)
	manager.dnf_happened.connect(_on_dnf)
	manager.sc_changed.connect(_on_sc)
	manager.overtake_happened.connect(_on_overtake)
	manager.race_finished.connect(_on_finish)


func _process(delta: float) -> void:
	if manager.paused or not manager.race_running:
		return
	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL:
		_poll_timer = 0.0
		_poll_player_cars()
		_poll_weather()


# ------------------------------------------------------------- event radio ---

func _on_pit(car: CarData, entering: bool) -> void:
	if not car.is_player:
		return
	if entering:
		_say("%s  |  Box confirmed, box." % car.short_code(), COL_NEUTRAL)
	else:
		_say("%s  |  Pit complete — %s fitted, go go go." % [car.short_code(), car.compound.display_name], COL_GOOD)


func _on_dnf(car: CarData) -> void:
	if car.is_player:
		_say("%s  |  No... we've lost the car. Mechanical failure." % car.short_code(), COL_BAD)
	else:
		_say("%s has retired on track." % car.display_name(), COL_NEUTRAL)


func _on_sc(phase: String) -> void:
	match phase:
		"deployed":
			_say("SAFETY CAR deployed — field bunching up. Pit window is cheap.", COL_SC)
		"ending":
			_say("Safety Car in this lap — prepare for the restart.", COL_SC)
		"restart":
			_say("Green flag green flag — GO GO GO!", COL_GOOD)


func _on_overtake(attacker: CarData, defender: CarData) -> void:
	if attacker.is_player:
		_say("%s  |  Lovely move on %s!" % [attacker.short_code(), defender.short_code()], COL_GOOD)
	elif defender.is_player:
		_say("%s  |  We lost the place to %s. Get it back." % [defender.short_code(), attacker.short_code()], COL_WARN)


func _on_finish(classification: Array) -> void:
	for i in classification.size():
		var car: CarData = classification[i]
		if car.is_player and not car.dnf:
			var msg := "%s  |  P%d. " % [car.short_code(), i + 1]
			msg += "YES! Great result!" if i < 6 else "Solid job today."
			_say(msg, COL_GOOD if i < 6 else COL_NEUTRAL)


# --------------------------------------------------------------- poll radio ---

func _poll_player_cars() -> void:
	for car: CarData in manager.player_cars():
		if car.finished or car.dnf or car.in_pit:
			continue
		var code: String = car.short_code()
		var opt: float = car.compound.optimal_temp_c

		if car.tyre_wear >= 0.62 and not car.pit_requested:
			_try("box_%d" % car.index, 60.0,
					"%s  |  Tyres at the limit — box this lap." % code, COL_BAD)
		elif car.tyre_wear >= 0.50:
			_try("wear_%d" % car.index, 180.0,
					"%s  |  Tyres are going off. Think about the stop." % code, COL_WARN)

		if car.tyre_temp_c > opt + 12.0:
			_try("hot_%d" % car.index, 90.0,
					"%s  |  Overheating the tyres — back off or go lean." % code, COL_WARN)

		if car.ers_charge >= 95.0 and car.ers_mode != CarData.ErsMode.DEPLOY \
				and car.ers_mode != CarData.ErsMode.OVERTAKE:
			_try("ers_%d" % car.index, 90.0,
					"%s  |  Battery full — use it." % code, COL_NEUTRAL)

		var laps_left: int = manager.engine.race_laps - car.laps_crossed
		if car.fuel_kg < laps_left * RaceEngine.BASE_FUEL_BURN_LAP * 0.96 \
				and car.fuel_mix != CarData.FuelMix.LEAN:
			_try("fuel_%d" % car.index, 120.0,
					"%s  |  Fuel is marginal — lean mix now." % code, COL_WARN)

		var gaps: Array = manager.gaps_around(car)
		if gaps[0] > 0.0 and gaps[0] < 1.0 and not manager.engine.sc_active:
			_try("attack_%d" % car.index, 45.0,
					"%s  |  You're in DRS range — have a go." % code, COL_GOOD)
		if gaps[1] > 0.0 and gaps[1] < 1.0 and not manager.engine.sc_active:
			_try("defend_%d" % car.index, 45.0,
					"%s  |  Car behind within DRS — defend." % code, COL_WARN)


func _poll_weather() -> void:
	var w: WeatherSystem = manager.engine.weather
	var forecast := w.forecast_text(manager.engine.sim_time,
			RaceManager.TIME_SCALES[manager.time_scale_index])
	if forecast != _last_forecast and forecast.begins_with("Rain in"):
		_say("Radar: %s. Plan the crossover." % forecast.to_lower(), COL_WARN)
	_last_forecast = forecast

	for car: CarData in manager.player_cars():
		if car.finished or car.dnf:
			continue
		if w.wetness > 0.32 and not TyreModel.is_rain_tyre(car.compound):
			_try("wet_%d" % car.index, 60.0,
					"%s  |  Too wet for slicks — inters are ready." % car.short_code(), COL_BAD)
		elif w.wetness < 0.16 and TyreModel.is_rain_tyre(car.compound) and w.intensity < 0.1:
			_try("dry_%d" % car.index, 60.0,
					"%s  |  Dry line forming — slicks are the call." % car.short_code(), COL_WARN)


# ---------------------------------------------------------------- plumbing ---

## Fire a message if its cooldown (in sim seconds) has expired.
func _try(key: String, cooldown_sim_s: float, text: String, color: Color) -> void:
	var now: float = manager.engine.sim_time
	if _cooldowns.get(key, -1e9) > now:
		return
	_cooldowns[key] = now + cooldown_sim_s
	_say(text, color)


func _say(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = "RADIO ›  " + text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	while get_child_count() > MAX_MESSAGES:
		get_child(0).free()
	var tween := label.create_tween()
	tween.tween_interval(MESSAGE_LIFETIME * 0.7)
	tween.tween_property(label, "modulate:a", 0.0, MESSAGE_LIFETIME * 0.3)
	tween.tween_callback(label.queue_free)
