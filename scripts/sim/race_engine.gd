class_name RaceEngine
extends RefCounted
## Segment-based race simulation (Motorsport Manager "TimeCost" style).
## Pure logic — zero Node dependencies, fully headless-testable and deterministic
## for a given seed. Only RaceManager talks to this object.

# ------------------------------------------------------------------ tuning ---
# Segment reference speeds (m/s) per corner class; straights use STRAIGHT_SPEED.
const CLASS_SPEEDS := {1: 26.0, 2: 42.0, 3: 62.0}
const STRAIGHT_SPEED := 78.0

# Seconds per lap gained across the full 0-100 stat range.
const DRIVER_PACE_LAP_GAIN := 1.2
const CAR_AERO_LAP_GAIN := 1.4       # applied on corner time share
const CAR_POWER_LAP_GAIN := 1.4      # applied on straight time share
const CAR_CHASSIS_LAP_GAIN := 0.5    # applied everywhere

# Grip multiplier -> time multiplier strength.
const GRIP_TIME_CORNER := 0.50
const GRIP_TIME_STRAIGHT := 0.15

# Fuel.
const FUEL_PENALTY_S_PER_KG_LAP := 0.03
const BASE_FUEL_BURN_LAP := 1.65     # kg/lap at standard mix
const FUEL_LOAD_MARGIN := 1.03
const FUEL_EMPTY_TIME_FACTOR := 1.5  # crawling home
const MIX_BURN := [0.85, 1.0, 1.22]  # LEAN, STANDARD, RICH
const MIX_TIME_LAP := [0.25, 0.0, -0.25]

# ERS (charge is 0-100).
const ERS_CHARGE_LAP := [7.0, 2.5, -9.0, -22.0]     # HARVEST, NEUTRAL, DEPLOY, OVERTAKE
const ERS_TIME_LAP := [0.18, 0.0, -0.38, -0.75]     # harvest penalty on corners, deploy bonus on straights

# Aero interaction.
const SLIPSTREAM_GAP_S := 1.0
const DRS_TIME_FACTOR := 0.965       # straight time multiplier when DRS is open
const DIRTY_AIR_CORNER_FACTOR := 0.018
const DIRTY_AIR_WEAR_MAX := 0.15
const DIRTY_AIR_PUSH := 0.15

# Driver noise: sigma per lap, reduced by consistency.
const NOISE_LAP_SIGMA_BASE := 0.35
const NOISE_SIGMA_PER_CONSISTENCY := 0.0025

# Battles.
const MIN_GAP_S := 0.4               # train clamp distance behind a blocked leader
const ATTACK_COOLDOWN_SEGMENTS := 4

# Race procedure.
const START_SPACING_M := 7.0
const PIT_STOP_SIGMA := 1.0

# Tyre temperature push contributions.
const PUSH_DEPLOY := 0.08
const PUSH_OVERTAKE := 0.18
const PUSH_RICH := 0.10
const PUSH_LEAN := -0.08
const PUSH_SLIDING := 0.5            # scaled by (1 - grip): worn tyres slide and overheat

# Setup & confidence.
const SETUP_MISMATCH_LAP := 0.22     # s/lap penalty per unit of (bias - track ideal)^2
const CONFIDENCE_LAP_GAIN := 0.30    # s/lap swing across confidence 0-100

# Rain driving.
const WET_NOISE_MULT := 1.5          # extra driver noise at full wetness
# AI compound-switch wetness thresholds (individual hesitation applied on top).
const AI_TO_INTER := 0.30
const AI_TO_WET := 0.68
const AI_WET_TO_INTER := 0.52
const AI_TO_SLICK := 0.16

# Reliability -> mechanical failure. fail/lap at reliability 100 and 70.
const FAIL_PER_LAP_BEST := 0.00015
const FAIL_PER_LAP_WORST := 0.0045

# Safety car.
const SC_CHANCE_ON_DNF := 0.55
const SC_MIN_LAPS_LEFT := 3          # no SC this close to the flag
const SC_QUEUE_PACE := 1.45          # segment-time multiplier at the head of the queue
const SC_CATCH_PACE := 1.16          # cars far from the queue close in at this pace
const SC_CATCH_GAP_S := 1.5
const SC_TEMP_PUSH := 0.55           # tyres cool down behind the safety car
const SC_ERS_BONUS_LAP := 4.0        # free harvesting under SC
# ------------------------------------------------------------------------------

var track: TrackData
var race_laps: int = 25
var cars: Array = []                 # Array[CarData], stable creation order (index = CarData.index)
var order: Array = []                # Array[CarData], sorted by race position
var events: Array = []               # dicts drained by RaceManager each tick
var sim_time: float = 0.0
var race_over: bool = false
var weather := WeatherSystem.new()   # DRY unless setup() gets a configured one

# Safety car state.
var sc_active := false
var sc_ending := false               # "safety car in this lap"
var _sc_laps_remaining := 0
var _sc_leader_lap_seen := -1

var _rng := RandomNumberGenerator.new()
## Time already consumed inside the current tick when a segment completes —
## gives lap/finish times millisecond precision instead of tick quantization.
var _tick_time_offset := 0.0
var _allowed_compounds: Array = []   # Array[TyreCompound]
var _track_len: float = 0.0
var _seg_base_times: PackedFloat32Array = []
var _seg_shares: PackedFloat32Array = []       # segment share of an ideal lap (by time)
var _seg_straight_shares: PackedFloat32Array = []  # share of total straight time (0 for corners)
var _seg_corner_shares: PackedFloat32Array = []    # share of total corner time (0 for straights)
var _base_lap_total: float = 0.0


# =========================================================== setup & commands =

## entries: [{team, driver, setup_bias?, confidence?, reliability?}, ...]
## p_weather: a configured WeatherSystem, or null for a dry race.
## use_entry_order: entries are already grid-sorted (external qualifying) —
## skip the internal quali sim.
func setup(p_track: TrackData, entries: Array, p_laps: int, allowed_compounds: Array,
		player_team_id: String, seed_value: int = 0, p_weather: WeatherSystem = null,
		use_entry_order: bool = false) -> void:
	track = p_track
	race_laps = p_laps
	_allowed_compounds = allowed_compounds
	_rng.seed = seed_value if seed_value != 0 else randi()
	_track_len = track.total_length_m()
	_precompute_segment_times()
	if p_weather:
		weather = p_weather

	cars.clear()
	for entry in entries:
		var car := CarData.new()
		car.index = cars.size()
		car.team = entry.team
		car.driver = entry.driver
		car.is_player = entry.team.id == player_team_id
		car.setup_bias = entry.get("setup_bias", track.df_bias)
		car.confidence = entry.get("confidence", 50.0)
		car.reliability = entry.get("reliability", 90.0)
		car.fuel_kg = race_laps * BASE_FUEL_BURN_LAP * FUEL_LOAD_MARGIN
		cars.append(car)

	if use_entry_order:
		for i in cars.size():
			cars[i].grid_pos = i + 1
	else:
		_run_qualifying()
	_place_grid()
	order = cars.duplicate()
	order.sort_custom(_position_sort)
	for car in cars:
		car.segment_time = _compute_segment_time(car)


func set_ers_mode(car_index: int, mode: int) -> void:
	cars[car_index].ers_mode = mode


func set_fuel_mix(car_index: int, mix: int) -> void:
	cars[car_index].fuel_mix = mix


func request_pit(car_index: int, compound: TyreCompound) -> void:
	var car: CarData = cars[car_index]
	car.pit_requested = true
	car.pit_target_compound = compound


func cancel_pit(car_index: int) -> void:
	cars[car_index].pit_requested = false


func get_classification() -> Array:
	return order


# ==================================================================== ticking =

func tick(sim_dt: float) -> void:
	if race_over:
		return
	weather.tick(sim_time, sim_dt)
	for car in order:
		if not car.finished and not car.dnf:
			_advance_car(car, sim_dt)
	sim_time += sim_dt
	order.sort_custom(_position_sort)
	_update_gaps()
	OvertakeResolver.resolve_all(self)
	_update_safety_car()
	if _all_finished():
		race_over = true
		events.append({"type": "race_finished"})


func _update_safety_car() -> void:
	if not sc_active or order.is_empty():
		return
	var leader: CarData = order[0]
	if leader.laps_crossed <= _sc_leader_lap_seen:
		return
	_sc_leader_lap_seen = leader.laps_crossed
	if sc_ending:
		sc_active = false
		sc_ending = false
		events.append({"type": "sc", "phase": "restart"})
	else:
		_sc_laps_remaining -= 1
		if _sc_laps_remaining <= 0:
			sc_ending = true
			events.append({"type": "sc", "phase": "ending"})


func _try_deploy_safety_car(cause_car: CarData) -> void:
	if sc_active or race_laps - cause_car.laps_crossed < SC_MIN_LAPS_LEFT:
		return
	if _rng.randf() < SC_CHANCE_ON_DNF:
		sc_active = true
		sc_ending = false
		_sc_laps_remaining = _rng.randi_range(2, 3)
		_sc_leader_lap_seen = order[0].laps_crossed if not order.is_empty() else 0
		events.append({"type": "sc", "phase": "deployed"})


func _advance_car(car: CarData, dt: float) -> void:
	car.total_race_time += dt
	if car.in_pit:
		car.pit_time_remaining -= dt
		if car.pit_time_remaining <= 0.0:
			_exit_pit(car)
		return

	var remaining := dt
	while remaining > 0.0 and not car.finished:
		var time_left := (1.0 - car.segment_progress) * car.segment_time
		if remaining < time_left:
			car.segment_progress += remaining / car.segment_time
			remaining = 0.0
		else:
			remaining -= time_left
			_tick_time_offset = dt - remaining
			_on_segment_complete(car)
			if car.finished or car.in_pit:
				break
			car.segment_time = _compute_segment_time(car)
			car.segment_progress = 0.0
	_refresh_race_distance(car)


func _on_segment_complete(car: CarData) -> void:
	var seg := track.get_segment(car.segment_index)
	_apply_segment_side_effects(car, seg)
	if car.attack_cooldown > 0:
		car.attack_cooldown -= 1

	# Mechanical failure roll (reliability comes from R&D risk history).
	var fail_per_lap: float = lerpf(FAIL_PER_LAP_BEST, FAIL_PER_LAP_WORST,
			clampf((100.0 - car.reliability) / 30.0, 0.0, 1.0))
	if _rng.randf() < fail_per_lap * _seg_shares[car.segment_index]:
		car.dnf = true
		car.in_battle = false
		events.append({"type": "dnf", "car": car})
		_try_deploy_safety_car(car)
		return

	car.segment_index += 1
	if car.segment_index >= track.segment_count():
		car.segment_index = 0
		car.laps_crossed += 1
		_on_line_crossed(car)


func _on_line_crossed(car: CarData) -> void:
	# Guard against re-crossing after a battle clamp pulled the car back over the line.
	if car.laps_crossed <= car.max_lap_seen:
		return
	car.max_lap_seen = car.laps_crossed

	var now := sim_time + _tick_time_offset
	if car.laps_crossed > 0:
		var lap_time := now - car.current_lap_start_time
		car.last_lap_time = lap_time
		if car.best_lap_time == 0.0 or lap_time < car.best_lap_time:
			car.best_lap_time = lap_time
		events.append({"type": "lap", "car": car, "lap": car.laps_crossed, "time": lap_time})
	car.current_lap_start_time = now
	car.lap = mini(car.laps_crossed + 1, race_laps)

	if car.laps_crossed >= race_laps:
		car.finished = true
		car.finish_time = now
		events.append({"type": "finish", "car": car})
		return

	if car.pit_requested:
		_enter_pit(car)
	elif not car.is_player:
		_ai_lap_decisions(car)


func _enter_pit(car: CarData) -> void:
	car.in_pit = true
	car.pit_requested = false
	car.pit_time_remaining = maxf(track.pit_lane_time_loss + _rng.randfn(0.0, PIT_STOP_SIGMA), 12.0)
	car.pit_count += 1
	events.append({"type": "pit_in", "car": car})


func _exit_pit(car: CarData) -> void:
	car.in_pit = false
	if car.pit_target_compound:
		car.compound = car.pit_target_compound
	car.tyre_wear = 0.0
	car.tyre_temp_c = 78.0
	car.segment_time = _compute_segment_time(car)
	car.segment_progress = 0.0
	events.append({"type": "pit_out", "car": car})


# ============================================================ timecost model =

## The heart of the sim: traversal time for the car's current segment.
func _compute_segment_time(car: CarData) -> float:
	var seg := track.get_segment(car.segment_index)
	var i := car.segment_index
	var base := _seg_base_times[i]
	var share := _seg_shares[i]
	var is_corner := seg.type == TrackSegment.Type.CORNER
	var t := base

	# Safety car: a parade, not a race. Cars far behind close up to the queue.
	if sc_active:
		var in_queue: bool = car == order[0] or car.gap_ahead_s < SC_CATCH_GAP_S
		return base * (SC_QUEUE_PACE if in_queue else SC_CATCH_PACE)

	# Tyre grip (dominant on corners), including compound-vs-wetness match.
	var grip := TyreModel.grip(car.compound, car.tyre_wear, car.tyre_temp_c, weather.wetness)
	var grip_strength := GRIP_TIME_CORNER if is_corner else GRIP_TIME_STRAIGHT
	t *= 1.0 + (1.0 - grip) * grip_strength

	# Setup: parabolic penalty away from the track's ideal downforce balance.
	var setup_err := car.setup_bias - track.df_bias
	t += SETUP_MISMATCH_LAP * setup_err * setup_err * share

	# Driver confidence.
	t -= (car.confidence - 50.0) / 100.0 * CONFIDENCE_LAP_GAIN * share

	# Dirty air: corners only, within the slipstream window.
	if is_corner and car.gap_ahead_s < SLIPSTREAM_GAP_S:
		t *= 1.0 + DIRTY_AIR_CORNER_FACTOR * (1.0 - car.gap_ahead_s / SLIPSTREAM_GAP_S)

	# DRS: designated straights, within 1s at the detection point.
	car.drs_open = seg.drs_zone and not is_corner and car.gap_ahead_s < SLIPSTREAM_GAP_S
	if car.drs_open:
		t *= DRS_TIME_FACTOR

	# Fuel weight + mixture.
	t += car.fuel_kg * FUEL_PENALTY_S_PER_KG_LAP * share
	t += MIX_TIME_LAP[car.fuel_mix] * share
	if car.fuel_kg <= 0.0:
		t *= FUEL_EMPTY_TIME_FACTOR

	# Driver and car stats.
	t -= (car.driver.skill_pace / 100.0) * DRIVER_PACE_LAP_GAIN * share
	t -= (car.team.stat_chassis / 100.0) * CAR_CHASSIS_LAP_GAIN * share
	if is_corner:
		t -= (car.team.stat_aero / 100.0) * CAR_AERO_LAP_GAIN * _seg_corner_shares[i]
	else:
		t -= (car.team.stat_power / 100.0) * CAR_POWER_LAP_GAIN * _seg_straight_shares[i]

	# ERS.
	var mode := _effective_ers_mode(car)
	if mode == CarData.ErsMode.HARVEST and is_corner:
		t += ERS_TIME_LAP[mode] * _seg_corner_shares[i]
	elif (mode == CarData.ErsMode.DEPLOY or mode == CarData.ErsMode.OVERTAKE) and not is_corner:
		t += ERS_TIME_LAP[mode] * _seg_straight_shares[i]

	# Driver noise, scaled down to segment size; rain amplifies mistakes.
	var sigma_lap := NOISE_LAP_SIGMA_BASE - NOISE_SIGMA_PER_CONSISTENCY * car.driver.skill_consistency
	sigma_lap *= 1.0 + WET_NOISE_MULT * weather.wetness
	t += _rng.randfn(0.0, sigma_lap * sqrt(share))

	return maxf(t, base * 0.7)


func _apply_segment_side_effects(car: CarData, seg: TrackSegment) -> void:
	var i := car.segment_index
	var share := _seg_shares[i]
	var is_corner := seg.type == TrackSegment.Type.CORNER

	# Fuel burn.
	car.fuel_kg = maxf(car.fuel_kg - BASE_FUEL_BURN_LAP * MIX_BURN[car.fuel_mix] * share, 0.0)

	# ERS charge.
	var mode := _effective_ers_mode(car)
	var charge_delta: float = ERS_CHARGE_LAP[mode] * share
	if mode == CarData.ErsMode.HARVEST:
		charge_delta *= 0.8 + 0.4 * (car.team.stat_power / 100.0)
	if sc_active:
		charge_delta += SC_ERS_BONUS_LAP * share
	car.ers_charge = clampf(car.ers_charge + charge_delta, 0.0, 100.0)

	# Tyre temperature.
	var grip := TyreModel.grip(car.compound, car.tyre_wear, car.tyre_temp_c, weather.wetness)
	var push := 1.0 + PUSH_SLIDING * (1.0 - grip)
	if sc_active:
		push = SC_TEMP_PUSH
	match mode:
		CarData.ErsMode.DEPLOY: push += PUSH_DEPLOY
		CarData.ErsMode.OVERTAKE: push += PUSH_OVERTAKE
	match car.fuel_mix:
		CarData.FuelMix.RICH: push += PUSH_RICH
		CarData.FuelMix.LEAN: push += PUSH_LEAN
	var in_dirty_air := car.gap_ahead_s < SLIPSTREAM_GAP_S
	if in_dirty_air:
		push += DIRTY_AIR_PUSH
	car.tyre_temp_c += TyreModel.temp_delta(
			is_corner, car.tyre_temp_c, track.ambient_temp_c, push, weather.wetness)

	# Tyre wear.
	var dirty_factor := 1.0
	if is_corner and in_dirty_air:
		dirty_factor += DIRTY_AIR_WEAR_MAX * (1.0 - car.gap_ahead_s / SLIPSTREAM_GAP_S)
	car.tyre_wear = minf(car.tyre_wear + TyreModel.wear_delta(
			car.compound, car.tyre_temp_c, share,
			car.driver.skill_tyre_mgmt, car.team.stat_chassis, dirty_factor,
			weather.wetness), 1.0)


func _effective_ers_mode(car: CarData) -> int:
	var mode := car.ers_mode
	if (mode == CarData.ErsMode.DEPLOY or mode == CarData.ErsMode.OVERTAKE) and car.ers_charge <= 0.0:
		return CarData.ErsMode.NEUTRAL
	if mode == CarData.ErsMode.HARVEST and car.ers_charge >= 100.0:
		return CarData.ErsMode.NEUTRAL
	return mode


# ================================================================== position =

## Canonical ordering key. laps_crossed starts at -1 (grid is before the line).
func _refresh_race_distance(car: CarData) -> void:
	var seg_len := track.get_segment(car.segment_index).length_m
	car.race_distance_m = car.laps_crossed * _track_len \
			+ track.cum_length_m(car.segment_index) + car.segment_progress * seg_len
	car.current_speed = seg_len / maxf(car.segment_time, 0.001)


## Used by battle resolution to clamp/teleport a car to an exact distance.
func set_race_distance(car: CarData, d: float) -> void:
	var laps := floori(d / _track_len)
	var in_lap := d - laps * _track_len
	var seg := 0
	for i in range(track.segment_count() - 1, -1, -1):
		if in_lap >= track.cum_length_m(i):
			seg = i
			break
	var crossed_line_forward: bool = laps > car.laps_crossed
	car.laps_crossed = laps
	var new_seg: bool = seg != car.segment_index
	car.segment_index = seg
	var seg_res := track.get_segment(seg)
	car.segment_progress = clampf((in_lap - track.cum_length_m(seg)) / seg_res.length_m, 0.0, 1.0)
	if new_seg:
		car.segment_time = _compute_segment_time(car)
	_refresh_race_distance(car)
	# A swap can teleport a car forward over the s/f line — lap/finish logic must still run.
	if crossed_line_forward:
		_on_line_crossed(car)


func _update_gaps() -> void:
	for i in order.size():
		var car: CarData = order[i]
		if i == 0 or car.finished:
			car.gap_ahead_s = 99.0
			continue
		var ahead: CarData = order[i - 1]
		var dist_gap: float = ahead.race_distance_m - car.race_distance_m
		car.gap_ahead_s = dist_gap / maxf(car.current_speed, 1.0)


func _position_sort(a: CarData, b: CarData) -> bool:
	# Retirements always classify behind running/finished cars.
	if a.dnf != b.dnf:
		return b.dnf
	if a.dnf and b.dnf:
		return a.race_distance_m > b.race_distance_m
	if a.finished != b.finished:
		return a.finished
	if a.finished and b.finished:
		return a.finish_time < b.finish_time
	return a.race_distance_m > b.race_distance_m


func _all_finished() -> bool:
	for car in cars:
		if not car.finished and not car.dnf:
			return false
	return true


# ==================================================================== ai =====

func _ai_lap_decisions(car: CarData) -> void:
	var laps_remaining := race_laps - car.laps_crossed

	# Weather call first: being on the wrong tyre costs seconds per lap.
	# Small per-driver hesitation so the field doesn't box in the same lap.
	var hesitation := (70.0 - car.driver.skill_consistency) / 700.0
	var w := weather.wetness
	var weather_target: TyreCompound = null
	if not TyreModel.is_rain_tyre(car.compound):
		if w > AI_TO_WET + hesitation:
			weather_target = _find_compound("wet")
		elif w > AI_TO_INTER + hesitation:
			weather_target = _find_compound("inter")
	elif car.compound.id == "inter":
		if w > AI_TO_WET + hesitation:
			weather_target = _find_compound("wet")
		elif w < AI_TO_SLICK - hesitation:
			weather_target = _ai_pick_compound(laps_remaining)
	elif car.compound.id == "wet":
		if w < AI_TO_SLICK - hesitation:
			weather_target = _ai_pick_compound(laps_remaining)
		elif w < AI_WET_TO_INTER - hesitation:
			weather_target = _find_compound("inter")
	if weather_target and weather_target != car.compound and laps_remaining >= 1:
		car.pit_requested = true
		car.pit_target_compound = weather_target
		_enter_pit(car)
		return

	# Safety car = cheap stop: freshen up if the tyres are half gone.
	if sc_active and not sc_ending and car.tyre_wear >= 0.45 and laps_remaining >= 4:
		car.pit_requested = true
		car.pit_target_compound = _ai_pick_compound(laps_remaining)
		_enter_pit(car)
		return

	# Pit call: box before the cliff, never with a handful of laps left.
	if car.tyre_wear >= 0.60 and laps_remaining >= 3:
		car.pit_requested = true
		car.pit_target_compound = _ai_pick_compound(laps_remaining)
		_enter_pit(car)
		return

	# ERS heuristic.
	if car.ers_charge < 15.0:
		car.ers_mode = CarData.ErsMode.HARVEST
	elif car.gap_ahead_s < 0.8 and car.ers_charge > 35.0:
		car.ers_mode = CarData.ErsMode.OVERTAKE
	elif car.ers_charge > 75.0:
		car.ers_mode = CarData.ErsMode.DEPLOY
	else:
		car.ers_mode = CarData.ErsMode.NEUTRAL

	# Fuel heuristic.
	var needed := laps_remaining * BASE_FUEL_BURN_LAP
	if car.fuel_kg < needed * 0.97:
		car.fuel_mix = CarData.FuelMix.LEAN
	elif car.fuel_kg > needed * 1.08:
		car.fuel_mix = CarData.FuelMix.RICH
	else:
		car.fuel_mix = CarData.FuelMix.STANDARD


func _ai_pick_compound(laps_remaining: int) -> TyreCompound:
	var want := "hard"
	if laps_remaining <= 8:
		want = "soft"
	elif laps_remaining <= 16:
		want = "medium"
	for c in _allowed_compounds:
		if c.id == want:
			return c
	return _allowed_compounds[0]


# ================================================================ procedure ===

func _run_qualifying() -> void:
	var ranked := cars.duplicate()
	ranked.sort_custom(func(a: CarData, b: CarData) -> bool:
		return _quali_score(a) > _quali_score(b))
	for i in ranked.size():
		ranked[i].grid_pos = i + 1


func _quali_score(car: CarData) -> float:
	var team_stat: float = (car.team.stat_aero + car.team.stat_power + car.team.stat_chassis) / 3.0
	return team_stat * 0.6 + car.driver.skill_pace * 0.4 + _rng.randfn(0.0, 2.5)


func _place_grid() -> void:
	var soft := _find_compound("soft")
	var medium := _find_compound("medium")
	# Wet grid: everyone starts on the appropriate rain tyre.
	var forced: TyreCompound = null
	if weather.wetness > AI_TO_WET:
		forced = _find_compound("wet")
	elif weather.wetness > AI_TO_INTER:
		forced = _find_compound("inter")
	for car in cars:
		if forced:
			car.compound = forced
		else:
			car.compound = soft if (car.grid_pos <= 12 or medium == null) else medium
		car.pit_target_compound = medium if medium else soft
		car.laps_crossed = -1
		car.max_lap_seen = -1
		var behind: float = 5.0 + START_SPACING_M * car.grid_pos
		set_race_distance(car, -behind)
		car.total_race_time = 0.0


func _find_compound(id: String) -> TyreCompound:
	for c in _allowed_compounds:
		if c.id == id:
			return c
	return null


func _precompute_segment_times() -> void:
	var n := track.segment_count()
	_seg_base_times.resize(n)
	_seg_shares.resize(n)
	_seg_straight_shares.resize(n)
	_seg_corner_shares.resize(n)
	var total := 0.0
	var straight_total := 0.0
	var corner_total := 0.0
	for i in n:
		var seg := track.get_segment(i)
		var speed: float = STRAIGHT_SPEED if seg.type == TrackSegment.Type.STRAIGHT \
				else CLASS_SPEEDS[seg.corner_class]
		_seg_base_times[i] = seg.length_m / speed
		total += _seg_base_times[i]
		if seg.type == TrackSegment.Type.STRAIGHT:
			straight_total += _seg_base_times[i]
		else:
			corner_total += _seg_base_times[i]
	_base_lap_total = total
	for i in n:
		var seg := track.get_segment(i)
		_seg_shares[i] = _seg_base_times[i] / total
		if seg.type == TrackSegment.Type.STRAIGHT:
			_seg_straight_shares[i] = _seg_base_times[i] / straight_total
		else:
			_seg_corner_shares[i] = _seg_base_times[i] / corner_total


func rng() -> RandomNumberGenerator:
	return _rng
