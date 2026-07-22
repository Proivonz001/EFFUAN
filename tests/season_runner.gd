class_name SeasonRunner
extends RefCounted
## Automated full-career season used by `--test-season` (needs autoloads, so it
## runs inside the real game via main.gd rather than as a -s script).

var failures := 0


func run(tree: SceneTree) -> void:
	GameState.new_career()
	var series: SeriesData = GameState.player_series()
	var rounds: int = series.calendar_track_ids.size()

	for round_i in rounds:
		var track: TrackData = GameState.current_track()
		GameState.pending_weather = GameState.make_weather()
		GameState.pending_setup_bias = track.df_bias   # engineer-perfect setup
		GameState.pending_rnd = {"pillar": "aero", "risk": 1}

		var entries: Array = GameState.build_entries(GameState.player_series_id)
		GameState.pending_grid = GameState.run_qualifying(entries)

		var compounds: Array = []
		for cid in ["soft", "medium", "hard", "inter", "wet"]:
			compounds.append(GameData.compounds[cid])
		var engine := RaceEngine.new()
		engine.setup(track, GameState.pending_grid, GameState.player_series().race_laps,
				compounds, GameState.player_team_id, GameState.race_seed(),
				GameState.pending_weather, true)
		var ticks := 0
		while not engine.race_over and ticks < 20000:
			engine.tick(0.4)
			engine.events.clear()
			ticks += 1
		_check(engine.race_over, "round %d race finishes" % (round_i + 1))

		var winner: CarData = engine.get_classification()[0]
		print("Round %d/%d  %s  [%s]  ->  winner %s (%s)" % [round_i + 1, rounds,
				track.track_name, GameState.pending_weather.preview_text(),
				winner.short_code(), winner.team.team_name])
		GameState.apply_player_race(engine.get_classification())

	# ---------------------------------------------------------- assertions ---
	_check(GameState.season_over, "season flagged as over after %d rounds" % rounds)
	_check(GameState.promotion_report.size() >= 4, "promotion/relegation verdicts produced")
	for line in GameState.promotion_report:
		print("  " + line)

	_check(GameState.team_standings("effuan_one").size() == 10
			and GameState.team_standings("effuan_two").size() == 10,
			"both series still have 10 teams")
	var f1: Array = GameState.final_standings["effuan_one"]
	var f2: Array = GameState.final_standings["effuan_two"]
	_check(int(f1[0].points) > 0, "tier 1 champion has points (quick-sim ran)")
	_check(int(f2[0].points) > 0, "tier 2 champion has points")
	print("S1 champion: %s (%d)  |  S2 champion: %s (%d)" % [
			GameData.teams[f1[0].team_id].team_name, int(f1[0].points),
			GameData.teams[f2[0].team_id].team_name, int(f2[0].points)])

	var rnd_moved := false
	for tid in GameState.rnd_bonuses:
		var b: Dictionary = GameState.rnd_bonuses[tid]
		if b.aero != 0.0 or b.power != 0.0 or b.chassis != 0.0:
			rnd_moved = true
	_check(rnd_moved, "R&D development moved car stats")

	for did in GameState.confidence:
		var c: float = GameState.confidence[did]
		_check(c >= GameState.CONFIDENCE_MIN and c <= GameState.CONFIDENCE_MAX,
				"confidence in range for %s (%.0f)" % [did, c])

	_check(GameState.has_save(), "career autosaved")
	var loaded_ok: bool = GameState.load_career()
	_check(loaded_ok and GameState.season_over, "save loads back with season state")

	# Season 2 spot-check: next season starts cleanly after promotion swaps.
	GameState.start_next_season()
	_check(GameState.round_index == 0 and not GameState.season_over, "season 2 ready")
	var entries2: Array = GameState.build_entries(GameState.player_series_id)
	_check(entries2.size() == 20, "season 2 grid builds (20 cars)")

	if failures == 0:
		print("SEASON TEST: ALL PASSED")
		tree.quit(0)
	else:
		print("SEASON TEST: %d FAILURES" % failures)
		tree.quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + label)
