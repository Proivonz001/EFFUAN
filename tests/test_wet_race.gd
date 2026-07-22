extends SceneTree
## Forced-rain race: verifies the wet-weather loop end to end.
## Run: godot --headless --path . -s res://tests/test_wet_race.gd

var _failures := 0


func _initialize() -> void:
	var gd = load("res://autoload/game_data.gd").new()
	gd.load_all()

	var series: SeriesData = gd.series["effuan_two"]
	var track: TrackData = gd.tracks["track_01"]
	var entries: Array = gd.build_entries(series)

	var compounds: Array = []
	for cid in ["soft", "medium", "hard", "inter", "wet"]:
		compounds.append(gd.compounds[cid])

	# Hand-built storm: dry start, heavy rain arriving early and staying.
	var weather := WeatherSystem.new()
	weather.scenario = WeatherSystem.Scenario.BUILDING_RAIN
	weather.wetness = 0.0
	weather._timeline = [
		{"t": 0.0, "i": 0.0},
		{"t": 300.0, "i": 0.0},
		{"t": 450.0, "i": 0.9},
		{"t": 99999.0, "i": 0.9},
	]

	var engine := RaceEngine.new()
	engine.setup(track, entries, series.race_laps, compounds, "", 4242, weather)

	var max_wetness := 0.0
	var max_rain_tyres := 0
	var rain_pits := 0
	var dnfs := 0
	var ticks := 0
	while not engine.race_over and ticks < 20000:
		engine.tick(0.4)
		for ev in engine.events:
			if ev.type == "pit_out" and TyreModel.is_rain_tyre(ev.car.compound):
				rain_pits += 1
			elif ev.type == "dnf":
				dnfs += 1
		engine.events.clear()
		max_wetness = maxf(max_wetness, engine.weather.wetness)
		var on_rain := 0
		for car in engine.cars:
			if TyreModel.is_rain_tyre(car.compound):
				on_rain += 1
		max_rain_tyres = maxi(max_rain_tyres, on_rain)
		ticks += 1

	print("=== WET RACE: wetness max %.2f | rain-tyre peak %d/20 | rain pit exits %d | DNFs %d ===" \
			% [max_wetness, max_rain_tyres, rain_pits, dnfs])
	var classification: Array = engine.get_classification()
	for i in mini(5, classification.size()):
		var c: CarData = classification[i]
		print("P%d %s (%s, wear %d%%)" % [i + 1, c.short_code(), c.compound.id, int(c.tyre_wear * 100)])

	_assert(engine.race_over, "race finishes despite the storm")
	_assert(max_wetness > 0.5, "track gets properly wet (%.2f)" % max_wetness)
	_assert(max_rain_tyres >= 16, "nearly the whole field switches to rain tyres (peak %d)" % max_rain_tyres)
	_assert(rain_pits >= 16, "rain tyre pit stops happened (%d)" % rain_pits)

	# Sanity: grip curves produce the expected crossovers.
	var soft: TyreCompound = gd.compounds["soft"]
	var inter: TyreCompound = gd.compounds["inter"]
	var wet: TyreCompound = gd.compounds["wet"]
	_assert(TyreModel.wet_factor(soft, 0.1) > TyreModel.wet_factor(inter, 0.1),
			"slick beats inter on a damp track")
	_assert(TyreModel.wet_factor(inter, 0.45) > TyreModel.wet_factor(soft, 0.45),
			"inter beats slick at wetness 0.45")
	_assert(TyreModel.wet_factor(wet, 0.85) > TyreModel.wet_factor(inter, 0.85),
			"full wet beats inter at wetness 0.85")

	if _failures == 0:
		print("WET RACE TEST: ALL PASSED")
		quit(0)
	else:
		print("WET RACE TEST: %d FAILURES" % _failures)
		quit(1)


func _assert(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: " + label)
