extends Node
## Career state singleton: season, standings, R&D, confidence, promotion.
## GameData holds immutable content; this holds everything that changes.

const SAVE_PATH := "user://career.json"
const SERIES_IDS := ["effuan_one", "effuan_two"]
const RELEGATION_SPOTS := 2

# R&D is XP-driven (F1-game style): weekend performance earns dev points,
# spent on upgrades that take N races to be delivered.
const UPGRADE_VARIANTS := [
	{"name": "CONSERVATIVE", "gain": 1.5, "rel": 0.5, "cost": 25, "races": 1},
	{"name": "STANDARD", "gain": 2.5, "rel": -0.5, "cost": 35, "races": 2},
	{"name": "AGGRESSIVE", "gain": 4.0, "rel": -2.0, "cost": 40, "races": 2},
]
const RELIABILITY_FIX := {"name": "RELIABILITY FIX", "gain": 0.0, "rel": 3.0, "cost": 20, "races": 1}
const MAX_ACTIVE_UPGRADES := 2
const XP_BASE_PER_WEEKEND := 10

const CONFIDENCE_SETUP_BONUS := 3.0
const CONFIDENCE_MIN := 15.0
const CONFIDENCE_MAX := 95.0

var career_active := false
var season := 1
var round_index := 0                 # next race to run, 0-based
var player_team_id := "aquila"
var player_series_id := "effuan_two"

## series_id -> {team_ids: Array, driver_points: {id: int}, team_points: {id: int}}
var series_state := {}
## team_id -> {aero, power, chassis, rel}
var rnd_bonuses := {}
## Player development: spendable XP + upgrades in delivery.
var dev_points := 0
## [{pillar, name, gain, rel, races_left}]
var active_upgrades: Array = []
## driver_id -> 0-100
var confidence := {}

# Set by the setup screen before the race launches.
var pending_setup_bias := 0.0
var pending_grid: Array = []         # entries pre-sorted by qualifying
var pending_weather: WeatherSystem = null

# Post-race / season-end display caches.
var last_player_result: Array = []   # engine classification (CarData refs)
var last_rnd_report := ""
var season_over := false
var promotion_report: Array = []     # strings for the season-end screen
## Final tables frozen BEFORE the promotion swap: {series_id: [{team_id, points}]}
var final_standings := {}


func new_career() -> void:
	career_active = true
	season = 1
	round_index = 0
	season_over = false
	player_team_id = "aquila"
	player_series_id = "effuan_two"
	series_state = {}
	rnd_bonuses = {}
	confidence = {}
	dev_points = 0
	active_upgrades = []
	for sid in SERIES_IDS:
		var s: SeriesData = GameData.series[sid]
		series_state[sid] = {
			"team_ids": Array(s.team_ids),
			"driver_points": {},
			"team_points": {},
		}
		for tid in s.team_ids:
			series_state[sid].team_points[tid] = 0
			for did in GameData.teams[tid].driver_ids:
				series_state[sid].driver_points[did] = 0
				confidence[did] = 50.0
	for tid in GameData.teams:
		rnd_bonuses[tid] = {"aero": 0.0, "power": 0.0, "chassis": 0.0, "rel": 0.0}
	GameData.player_team_id = player_team_id
	save_career()


# ------------------------------------------------------------ race context ---

func player_series() -> SeriesData:
	return GameData.series[player_series_id]


func current_track() -> TrackData:
	var s := player_series()
	return GameData.tracks[s.calendar_track_ids[round_index]]


func race_seed() -> int:
	return hash("s%d_r%d" % [season, round_index])


func make_weather() -> WeatherSystem:
	var s := player_series()
	var track := current_track()
	var w := WeatherSystem.new()
	w.setup(race_seed() + 77, s.race_laps * track.base_lap_time)
	return w


## Team with R&D bonuses applied (duplicate — content resources stay pristine).
func effective_team(team_id: String) -> TeamData:
	var team: TeamData = GameData.teams[team_id]
	var b: Dictionary = rnd_bonuses.get(team_id, {})
	var eff: TeamData = team.duplicate()
	eff.stat_aero = clampf(team.stat_aero + b.get("aero", 0.0), 0.0, 100.0)
	eff.stat_power = clampf(team.stat_power + b.get("power", 0.0), 0.0, 100.0)
	eff.stat_chassis = clampf(team.stat_chassis + b.get("chassis", 0.0), 0.0, 100.0)
	eff.stat_reliability = clampf(team.stat_reliability + b.get("rel", 0.0), 60.0, 99.0)
	return eff


## Engine entries for a series, in stable team order (unsorted by pace).
func build_entries(series_id: String) -> Array:
	var out: Array = []
	var track := current_track()
	var rng := RandomNumberGenerator.new()
	rng.seed = race_seed() + hash(series_id)
	for tid in series_state[series_id].team_ids:
		var eff := effective_team(tid)
		for did in eff.driver_ids:
			var is_player: bool = tid == player_team_id
			var bias: float = pending_setup_bias if is_player \
					else clampf(track.df_bias + rng.randfn(0.0, 0.18), -1.0, 1.0)
			out.append({
				"team": eff,
				"driver": GameData.drivers[did],
				"setup_bias": bias,
				"confidence": confidence.get(did, 50.0),
				"reliability": eff.stat_reliability,
			})
	return out


## Simplified qualifying: one flying lap per car, returns entries sorted P1-first
## with the lap time stored under "quali_time".
func run_qualifying(entries: Array) -> Array:
	var track := current_track()
	var wet: float = pending_weather.wetness if pending_weather else 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = race_seed() + 999
	for e in entries:
		var team: TeamData = e.team
		var driver: DriverData = e.driver
		var stat_gain: float = (team.stat_aero + team.stat_power + team.stat_chassis) / 3.0 * 0.022 \
				+ driver.skill_pace * 0.014 + (e.confidence - 50.0) * 0.004
		var setup_err: float = e.setup_bias - track.df_bias
		var noise_sigma: float = (0.45 - driver.skill_consistency * 0.002) * (1.0 + wet * 1.5)
		e["quali_time"] = track.base_lap_time - stat_gain \
				+ RaceEngine.SETUP_MISMATCH_LAP * setup_err * setup_err \
				+ (0.9 * wet) + rng.randfn(0.0, noise_sigma)
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a, b): return a.quali_time < b.quali_time)
	return sorted


# ------------------------------------------------------------- post race -----

## Called once when the player's race ends. Awards points for both series,
## resolves R&D, updates confidence, advances the calendar.
func apply_player_race(classification: Array) -> void:
	last_player_result = classification
	var s := player_series()
	var results: Array = []
	for car in classification:
		results.append({
			"driver_id": car.driver.id,
			"team_id": car.team.id,
			"dnf": car.dnf,
			"expected": car.grid_pos,
		})
	_award_points(player_series_id, results)
	_update_confidence(results)
	_earn_dev_points(results)

	var other_id: String = "effuan_one" if player_series_id == "effuan_two" else "effuan_two"
	_quick_sim_series(other_id)
	_advance_upgrades()
	_ai_development()

	round_index += 1
	if round_index >= s.calendar_track_ids.size():
		_end_season()
	pending_grid = []
	pending_weather = null
	save_career()


func _award_points(series_id: String, results: Array) -> void:
	var s: SeriesData = GameData.series[series_id]
	var st: Dictionary = series_state[series_id]
	var scoring := 0
	for r in results:
		if r.dnf:
			continue
		if scoring < s.points_table.size():
			st.driver_points[r.driver_id] += s.points_table[scoring]
			st.team_points[r.team_id] += s.points_table[scoring]
		scoring += 1


func _update_confidence(results: Array) -> void:
	var track := current_track()
	for i in results.size():
		var r: Dictionary = results[i]
		var delta: float
		if r.dnf:
			delta = -6.0
		else:
			delta = clampf((r.expected - (i + 1)) * 1.5, -8.0, 8.0)
		if r.team_id == player_team_id and not r.dnf \
				and absf(pending_setup_bias - track.df_bias) < 0.15:
			delta += CONFIDENCE_SETUP_BONUS
		confidence[r.driver_id] = clampf(
				confidence.get(r.driver_id, 50.0) + delta, CONFIDENCE_MIN, CONFIDENCE_MAX)


## Statistical background race for the series the player is not in.
func _quick_sim_series(series_id: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = race_seed() + hash(series_id) + 5
	var scored: Array = []
	for tid in series_state[series_id].team_ids:
		var eff := effective_team(tid)
		for did in eff.driver_ids:
			var driver: DriverData = GameData.drivers[did]
			var quality: float = (eff.stat_aero + eff.stat_power + eff.stat_chassis) / 3.0 * 0.6 \
					+ driver.skill_pace * 0.4 + rng.randfn(0.0, 5.0)
			var dnf: bool = rng.randf() < (100.0 - eff.stat_reliability) / 30.0 * 0.07
			scored.append({"driver_id": did, "team_id": tid, "dnf": dnf,
					"expected": 0, "q": quality})
	scored.sort_custom(func(a, b): return a.q > b.q)
	_award_points(series_id, scored)
	# Light confidence drift for the other series so it doesn't fossilize.
	for i in scored.size():
		var did: String = scored[i].driver_id
		var drift := -1.0 if scored[i].dnf else clampf((scored.size() * 0.5 - i) * 0.3, -2.0, 2.0)
		confidence[did] = clampf(confidence.get(did, 50.0) + drift, CONFIDENCE_MIN, CONFIDENCE_MAX)


# -------------------------------------------------------------- R&D / XP -----

## Weekend performance -> dev points. Base income + championship points scored
## + a bonus for every position gained versus the starting grid.
func _earn_dev_points(results: Array) -> void:
	var s := player_series()
	var earned := XP_BASE_PER_WEEKEND
	var scoring := 0
	for i in results.size():
		var r: Dictionary = results[i]
		if not r.dnf:
			if r.team_id == player_team_id and scoring < s.points_table.size():
				earned += s.points_table[scoring]
			scoring += 1
		if r.team_id == player_team_id and not r.dnf:
			earned += maxi(0, int(r.expected) - (i + 1)) * 2
	dev_points += earned
	last_rnd_report = "Weekend development: +%d XP (bank %d)" % [earned, dev_points]


## Called from the hub. Returns "" on success or a reason why not.
func purchase_upgrade(pillar: String, variant: Dictionary) -> String:
	if active_upgrades.size() >= MAX_ACTIVE_UPGRADES:
		return "Development slots full (%d in progress)" % active_upgrades.size()
	if dev_points < int(variant.cost):
		return "Not enough XP (%d needed)" % int(variant.cost)
	dev_points -= int(variant.cost)
	active_upgrades.append({
		"pillar": pillar, "name": variant.name, "gain": variant.gain,
		"rel": variant.rel, "races_left": int(variant.races),
	})
	save_career()
	return ""


func _advance_upgrades() -> void:
	var delivered: Array = []
	for up in active_upgrades:
		up.races_left = int(up.races_left) - 1
		if up.races_left <= 0:
			if up.pillar != "reliability":
				rnd_bonuses[player_team_id][up.pillar] += up.gain
			rnd_bonuses[player_team_id]["rel"] += up.rel
			delivered.append(up)
	for up in delivered:
		active_upgrades.erase(up)
		last_rnd_report += "   |   DELIVERED: %s %s (%+.1f, rel %+.1f)" % [
				up.name, str(up.pillar).to_upper(), up.gain, up.rel]


## AI teams develop at a pace comparable to an average player.
func _ai_development() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = race_seed() + 31
	for tid in rnd_bonuses:
		if tid == player_team_id:
			continue
		if rng.randf() < 0.62:
			var pillar: String = ["aero", "power", "chassis"][rng.randi_range(0, 2)]
			rnd_bonuses[tid][pillar] += 2.0
			rnd_bonuses[tid]["rel"] += rng.randf_range(-0.6, 0.3)


# ------------------------------------------------------------- season end ----

func _end_season() -> void:
	season_over = true
	promotion_report = []
	# Freeze final tables before the swap corrupts who-belongs-where.
	final_standings = {}
	for sid in SERIES_IDS:
		var table: Array = []
		for entry in team_standings(sid):
			table.append({"team_id": entry.team.id, "points": int(entry.points)})
		final_standings[sid] = table
	var top: Dictionary = series_state["effuan_one"]
	var bottom: Dictionary = series_state["effuan_two"]
	var t1_order := _teams_by_points("effuan_one")
	var t2_order := _teams_by_points("effuan_two")

	var relegated: Array = t1_order.slice(t1_order.size() - RELEGATION_SPOTS)
	var promoted: Array = t2_order.slice(0, RELEGATION_SPOTS)
	for tid in relegated:
		top.team_ids.erase(tid)
		bottom.team_ids.append(tid)
		promotion_report.append("%s relegated to Series Two" % GameData.teams[tid].team_name)
	for tid in promoted:
		bottom.team_ids.erase(tid)
		top.team_ids.append(tid)
		promotion_report.append("%s promoted to Series One" % GameData.teams[tid].team_name)

	if player_team_id in promoted:
		player_series_id = "effuan_one"
		promotion_report.append(">>> YOUR TEAM IS PROMOTED! <<<")
	elif player_team_id in relegated:
		player_series_id = "effuan_two"
		promotion_report.append(">>> Your team is relegated. <<<")


func start_next_season() -> void:
	season += 1
	round_index = 0
	season_over = false
	for sid in SERIES_IDS:
		var st: Dictionary = series_state[sid]
		st.driver_points = {}
		st.team_points = {}
		for tid in st.team_ids:
			st.team_points[tid] = 0
			for did in GameData.teams[tid].driver_ids:
				st.driver_points[did] = 0
	save_career()


# --------------------------------------------------------------- queries -----

func _teams_by_points(series_id: String) -> Array:
	var st: Dictionary = series_state[series_id]
	var ids: Array = st.team_ids.duplicate()
	ids.sort_custom(func(a, b): return st.team_points.get(a, 0) > st.team_points.get(b, 0))
	return ids


func team_standings(series_id: String) -> Array:
	var st: Dictionary = series_state[series_id]
	var out: Array = []
	for tid in _teams_by_points(series_id):
		out.append({"team": GameData.teams[tid], "points": st.team_points.get(tid, 0)})
	return out


func driver_standings(series_id: String) -> Array:
	var st: Dictionary = series_state[series_id]
	var pairs: Array = []
	for did in st.driver_points:
		pairs.append({"driver": GameData.drivers[did], "points": st.driver_points[did],
				"team": _team_of_driver(did)})
	pairs.sort_custom(func(a, b): return a.points > b.points)
	return pairs


func _team_of_driver(driver_id: String) -> TeamData:
	for tid in GameData.teams:
		if driver_id in GameData.teams[tid].driver_ids:
			return GameData.teams[tid]
	return null


# ------------------------------------------------------------- save/load -----

func save_career() -> void:
	var data := {
		"season": season, "round_index": round_index,
		"player_team_id": player_team_id, "player_series_id": player_series_id,
		"series_state": series_state, "rnd_bonuses": rnd_bonuses,
		"confidence": confidence, "season_over": season_over,
		"promotion_report": promotion_report,
		"final_standings": final_standings,
		"dev_points": dev_points, "active_upgrades": active_upgrades,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_career() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		return false
	season = int(parsed.season)
	round_index = int(parsed.round_index)
	player_team_id = parsed.player_team_id
	player_series_id = parsed.player_series_id
	series_state = parsed.series_state
	rnd_bonuses = parsed.rnd_bonuses
	confidence = parsed.confidence
	season_over = parsed.season_over
	promotion_report = parsed.get("promotion_report", [])
	final_standings = parsed.get("final_standings", {})
	dev_points = int(parsed.get("dev_points", 0))
	active_upgrades = parsed.get("active_upgrades", [])
	career_active = true
	GameData.player_team_id = player_team_id
	return true
