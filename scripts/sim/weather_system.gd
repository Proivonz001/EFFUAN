class_name WeatherSystem
extends RefCounted
## Deterministic per-race weather: a scenario picked from the seed generates a
## rain-intensity timeline; track wetness integrates rain vs drying each tick.
## Pure sim — the UI reads intensity/wetness/forecast, the engine reads wetness.

enum Scenario { DRY, SHOWER, WET_DRYING, BUILDING_RAIN }

# ------------------------------------------------------------------ tuning ---
const SCENARIO_WEIGHTS := [0.40, 0.25, 0.20, 0.15]
const WETTING_PER_S := 0.0020        # wetness gain/s at full rain intensity
const DRYING_PER_S := 0.0013        # wetness loss/s on a dry, rubbered-in track
# ------------------------------------------------------------------------------

var scenario: Scenario = Scenario.DRY
var wetness: float = 0.0             # 0 = bone dry, 1 = standing water
var intensity: float = 0.0           # current rainfall 0..1

## Timeline keyframes: {t: sim seconds, i: target intensity}, linear in between.
var _timeline: Array = []
var _race_duration: float = 2000.0


func setup(seed_value: int, race_duration_s: float) -> void:
	_race_duration = race_duration_s
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var roll := rng.randf()
	var acc := 0.0
	for s in SCENARIO_WEIGHTS.size():
		acc += SCENARIO_WEIGHTS[s]
		if roll < acc:
			scenario = s as Scenario
			break

	_timeline.clear()
	match scenario:
		Scenario.DRY:
			wetness = 0.0
			_timeline = [{"t": 0.0, "i": 0.0}]
		Scenario.SHOWER:
			wetness = 0.0
			var start := race_duration_s * rng.randf_range(0.25, 0.5)
			var length := rng.randf_range(360.0, 700.0)
			var peak := rng.randf_range(0.55, 0.95)
			_timeline = [
				{"t": 0.0, "i": 0.0},
				{"t": start, "i": 0.0},
				{"t": start + 90.0, "i": peak},
				{"t": start + length, "i": peak * 0.7},
				{"t": start + length + 120.0, "i": 0.0},
			]
		Scenario.WET_DRYING:
			wetness = rng.randf_range(0.5, 0.8)
			var stop := race_duration_s * rng.randf_range(0.1, 0.35)
			_timeline = [
				{"t": 0.0, "i": rng.randf_range(0.25, 0.5)},
				{"t": stop, "i": 0.15},
				{"t": stop + 150.0, "i": 0.0},
			]
		Scenario.BUILDING_RAIN:
			wetness = 0.0
			var start := race_duration_s * rng.randf_range(0.45, 0.7)
			_timeline = [
				{"t": 0.0, "i": 0.0},
				{"t": start, "i": 0.0},
				{"t": start + 200.0, "i": rng.randf_range(0.6, 1.0)},
				{"t": race_duration_s * 2.0, "i": 1.0},
			]


func tick(sim_time: float, sim_dt: float) -> void:
	intensity = _intensity_at(sim_time)
	var delta := intensity * WETTING_PER_S - (1.0 - intensity) * DRYING_PER_S
	wetness = clampf(wetness + delta * sim_dt, 0.0, 1.0)


func _intensity_at(t: float) -> float:
	if _timeline.is_empty():
		return 0.0
	if t <= _timeline[0].t:
		return _timeline[0].i
	for i in range(1, _timeline.size()):
		if t < _timeline[i].t:
			var a: Dictionary = _timeline[i - 1]
			var b: Dictionary = _timeline[i]
			return lerpf(a.i, b.i, (t - a.t) / maxf(b.t - a.t, 0.001))
	return _timeline[-1].i


# ----------------------------------------------------------------- UI helpers -

func condition_text() -> String:
	if intensity > 0.6:
		return "HEAVY RAIN"
	if intensity > 0.15:
		return "RAIN"
	if wetness > 0.45:
		return "WET TRACK"
	if wetness > 0.12:
		return "DRYING"
	return "DRY"


## Short forecast line for the pit wall, looking ahead from sim_time.
func forecast_text(sim_time: float, time_scale: float) -> String:
	var horizon := 1200.0
	var step := 30.0
	var t := sim_time
	while t < sim_time + horizon:
		var future := _intensity_at(t)
		if intensity <= 0.15 and future > 0.3:
			return "Rain in ~%d min" % maxi(int((t - sim_time) / time_scale / 60.0), 1)
		if intensity > 0.3 and future <= 0.15:
			return "Stopping in ~%d min" % maxi(int((t - sim_time) / time_scale / 60.0), 1)
		t += step
	if intensity > 0.15:
		return "Rain continues"
	return "No rain expected"


## Pre-race one-liner for the setup screen (whole-race outlook).
func preview_text() -> String:
	match scenario:
		Scenario.DRY: return "Dry race expected"
		Scenario.SHOWER: return "Showers possible mid-race"
		Scenario.WET_DRYING: return "Wet start, drying later"
		Scenario.BUILDING_RAIN: return "Rain arriving late in the race"
	return ""
