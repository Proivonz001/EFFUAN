extends SceneTree
## Safety car verification: low reliability forces DNFs, DNFs draw an SC.
## Checks: SC deploys, field compacts, no overtakes under SC, race finishes.
## Run: godot --headless --path . -s res://tests/test_safety_car.gd

var _failures := 0


func _initialize() -> void:
	var gd = load("res://autoload/game_data.gd").new()
	gd.load_all()
	var series: SeriesData = gd.series["effuan_one"]
	var track: TrackData = gd.tracks["track_01"]
	var compounds: Array = []
	for cid in series.allowed_compound_ids:
		compounds.append(gd.compounds[cid])

	var sc_seen := false
	var seed_used := 0
	for seed_try in [111, 222, 333, 444, 555]:
		var entries: Array = gd.build_entries(series)
		for e in entries:
			e["reliability"] = 70.0   # fragile grid -> DNFs -> SC draws
		var engine := RaceEngine.new()
		engine.setup(track, entries, series.race_laps, compounds, "", seed_try)

		var deployments := 0
		var overtakes_under_sc := 0
		var min_avg_gap_under_sc := 999.0
		var dnfs := 0
		var ticks := 0
		while not engine.race_over and ticks < 20000:
			engine.tick(0.4)
			for ev in engine.events:
				match ev.type:
					"sc":
						if ev.phase == "deployed":
							deployments += 1
					"overtake":
						if engine.sc_active:
							overtakes_under_sc += 1
					"dnf":
						dnfs += 1
			engine.events.clear()
			if engine.sc_active:
				var gaps := 0.0
				var counted := 0
				for i in range(1, mini(10, engine.order.size())):
					var car: CarData = engine.order[i]
					if not car.dnf and not car.finished and not car.in_pit:
						gaps += car.gap_ahead_s
						counted += 1
				if counted >= 5:
					min_avg_gap_under_sc = minf(min_avg_gap_under_sc, gaps / counted)
			ticks += 1

		if deployments > 0:
			sc_seen = true
			seed_used = seed_try
			print("seed %d: DNFs %d | SC deployments %d | overtakes under SC %d | tightest avg top-10 gap %.2fs" \
					% [seed_try, dnfs, deployments, overtakes_under_sc, min_avg_gap_under_sc])
			_assert(engine.race_over, "race finishes with SC interruptions")
			_assert(overtakes_under_sc == 0, "no overtakes under safety car (%d)" % overtakes_under_sc)
			_assert(min_avg_gap_under_sc < 1.2,
					"field compacts behind the SC (avg gap %.2fs)" % min_avg_gap_under_sc)
			break

	_assert(sc_seen, "at least one seed out of five produced a safety car")

	if _failures == 0:
		print("SAFETY CAR TEST: ALL PASSED (seed %d)" % seed_used)
		quit(0)
	else:
		print("SAFETY CAR TEST: %d FAILURES" % _failures)
		quit(1)


func _assert(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: " + label)
