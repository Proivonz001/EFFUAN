extends SceneTree
## Full headless race — the balance dashboard. Run after every tuning change:
## godot --headless --path . -s res://tests/headless_race.gd
## Autoloads don't run under -s, so GameData is instanced manually.

const TICK := 0.05
const TIME_SCALE := 8.0
const MAX_REAL_SECONDS := 12.0 * 60.0   # hard stop: sim must finish well before this

var _failures := 0


func _initialize() -> void:
	var gd = load("res://autoload/game_data.gd").new()
	gd.load_all()

	var series: SeriesData = gd.series["effuan_one"]
	var track: TrackData = gd.tracks["track_01"]
	var entries: Array = gd.build_entries(series)
	_assert(entries.size() == 20, "20 race entries (got %d)" % entries.size())

	var compounds: Array = []
	for cid in series.allowed_compound_ids:
		compounds.append(gd.compounds[cid])

	var engine := RaceEngine.new()
	engine.setup(track, entries, series.race_laps, compounds, "", 12345)

	var overtakes := 0
	var laps_logged := 0
	var ticks := 0
	var max_ticks := int(MAX_REAL_SECONDS / TICK)
	while not engine.race_over and ticks < max_ticks:
		engine.tick(TICK * TIME_SCALE)
		for ev in engine.events:
			match ev.type:
				"overtake": overtakes += 1
				"lap": laps_logged += 1
		engine.events.clear()
		ticks += 1

	var real_seconds := ticks * TICK
	print("\n=== RACE REPORT: %s, %d laps, seed 12345 ===" % [track.track_name, series.race_laps])
	print("Real duration at %.0fx: %.1f min (sim %.1f min)" % [TIME_SCALE, real_seconds / 60.0, engine.sim_time / 60.0])
	print("Overtakes: %d | Lap events: %d" % [overtakes, laps_logged])
	print("\nPos Code Team            Time/Gap   Best    Pits Tyre@End")
	var classification: Array = engine.get_classification()
	var leader: CarData = classification[0]
	for i in classification.size():
		var c: CarData = classification[i]
		var gap_str := "%.1fs" % (c.finish_time - leader.finish_time) if i > 0 and c.finished else "WINNER"
		if not c.finished:
			gap_str = "DNF/lap %d" % c.lap
		print("P%-3d %s  %-15s %-10s %6.2f  %d    %s w%.0f%%" % [
			i + 1, c.short_code(), c.team.team_name, gap_str, c.best_lap_time,
			c.pit_count, c.compound.id, c.tyre_wear * 100.0])

	# ------------------------------------------------------------ invariants ---
	_assert(engine.race_over, "race finished within the hard time cap")
	var real_min := real_seconds / 60.0
	_assert(real_min >= 3.0 and real_min <= 9.0, "race length 3-9 real min at 8x (got %.1f)" % real_min)

	var indices := {}
	for c in classification:
		indices[c.index] = true
	_assert(indices.size() == 20, "classification is a permutation of all cars")

	var total_pits := 0
	var pits_ok := true
	for c in classification:
		total_pits += c.pit_count
		if c.pit_count > 3:
			pits_ok = false
	_assert(pits_ok, "no car pits more than 3 times")
	_assert(total_pits >= 15, "most of the field pits at least once (total %d)" % total_pits)

	var best_overall := 999.0
	for c in classification:
		if c.best_lap_time > 0.0:
			best_overall = minf(best_overall, c.best_lap_time)
		_assert(c.best_lap_time == 0.0 or (c.best_lap_time > 60.0 and c.best_lap_time < 110.0),
				"best lap sane for %s (%.2f)" % [c.short_code(), c.best_lap_time])
	print("\nFastest lap overall: %.2f (anchor %.0f)" % [best_overall, track.base_lap_time])

	var spread: float = classification[19].finish_time - leader.finish_time if classification[19].finished else -1.0
	print("Field spread P1->P20: %.1f s" % spread)
	_assert(spread > 10.0 and spread < 150.0, "field spread 10-150s (got %.1f)" % spread)

	_assert(overtakes >= 10 and overtakes <= 120, "10-120 overtakes per race (got %d)" % overtakes)

	# Determinism: same seed, same winner and same winning time.
	var engine2 := RaceEngine.new()
	engine2.setup(track, entries, series.race_laps, compounds, "", 12345)
	while not engine2.race_over:
		engine2.tick(TICK * TIME_SCALE)
		engine2.events.clear()
	var w1: CarData = classification[0]
	var w2: CarData = engine2.get_classification()[0]
	_assert(w1.index == w2.index and absf(w1.finish_time - w2.finish_time) < 0.001,
			"deterministic with fixed seed")

	if _failures == 0:
		print("\nHEADLESS RACE: ALL CHECKS PASSED")
		quit(0)
	else:
		print("\nHEADLESS RACE: %d CHECK FAILURES" % _failures)
		quit(1)


func _assert(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: " + label)
