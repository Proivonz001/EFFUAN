class_name OvertakeResolver
extends RefCounted
## Battle resolution between adjacent cars on track. Called once per engine tick,
## after the position sort. Two outcomes when a car catches the one ahead:
## a clean swap, or the train clamp (held behind at MIN_GAP, inheriting the pace).

# ------------------------------------------------------------------ tuning ---
const BASE_PASS_CHANCE := 0.115       # divided by the zone's overtaking_difficulty
const PACE_DELTA_WEIGHT := 3.0        # relative pace difference -> chance
const SKILL_WEIGHT := 0.25            # (attacker overtaking - defender defending)/100
const DRS_BONUS := 0.15
const ERS_ATTACK_BONUS := 0.15        # attacker in OVERTAKE mode
const ERS_DEFEND_MALUS := 0.10        # defender in OVERTAKE mode
const BLUE_FLAG_CHANCE := 0.95
const MIN_CHANCE := 0.05
const MAX_CHANCE := 0.95
const SWAP_LEAD_M := 3.0              # attacker emerges this far ahead after a pass
const DEFENDER_TIME_LOSS := 1.03      # defender's current segment slowed after being passed
# ------------------------------------------------------------------------------


static func resolve_all(engine: RaceEngine) -> void:
	var order: Array = engine.order
	for i in range(1, order.size()):
		var leader: CarData = order[i - 1]
		var follower: CarData = order[i]
		if leader.finished or follower.finished or leader.in_pit or follower.in_pit \
				or leader.dnf or follower.dnf:
			follower.in_battle = false
			continue
		_resolve_pair(engine, leader, follower)


const DUEL_ALONGSIDE_M := 2.0         # sim gap while wheel-to-wheel (noses overlap visually)

static func _resolve_pair(engine: RaceEngine, leader: CarData, follower: CarData) -> void:
	var min_gap_m: float = RaceEngine.MIN_GAP_S * maxf(leader.current_speed, 1.0)

	# An active duel pins the pair side by side until the braking zone decides it.
	if follower.duel_with == leader.index and leader.duel_with == follower.index:
		follower.in_battle = true
		leader.in_battle = true
		engine.set_race_distance(follower, leader.race_distance_m - DUEL_ALONGSIDE_M)
		return

	var caught: bool = follower.race_distance_m > leader.race_distance_m - min_gap_m
	if not caught:
		follower.in_battle = false
		return

	follower.in_battle = true
	leader.in_battle = true

	# No overtaking under safety car — queue up only.
	if engine.sc_active:
		engine.set_race_distance(follower, leader.race_distance_m - min_gap_m)
		return

	# A car already busy in another duel just holds station.
	if follower.duel_with >= 0 or leader.duel_with >= 0:
		engine.set_race_distance(follower, leader.race_distance_m - min_gap_m)
		return

	if follower.attack_cooldown == 0:
		# The overtake becomes a DUEL: outcome pre-rolled here, the pair runs
		# wheel-to-wheel and the move resolves at the next corner entry.
		var chance := _pass_chance(engine, leader, follower)
		follower.attack_cooldown = RaceEngine.ATTACK_COOLDOWN_SEGMENTS
		follower.duel_with = leader.index
		follower.duel_role = 0
		follower.duel_success = engine.rng().randf() < chance
		follower.duel_t = 0.0
		follower.duel_lane = 1.0
		leader.duel_with = follower.index
		leader.duel_role = 1
		leader.duel_t = 0.0
		leader.duel_lane = -1.0
		engine.set_race_distance(follower, leader.race_distance_m - DUEL_ALONGSIDE_M)
		engine.events.append({"type": "duel", "attacker": follower, "defender": leader})
		return

	# Train clamp: held behind, inheriting the leader's effective pace.
	engine.set_race_distance(follower, leader.race_distance_m - min_gap_m)


static func _pass_chance(engine: RaceEngine, leader: CarData, follower: CarData) -> float:
	# Blue flags: lapped traffic barely resists.
	if leader.laps_crossed < follower.laps_crossed:
		return BLUE_FLAG_CHANCE

	var seg: TrackSegment = engine.track.get_segment(follower.segment_index)
	var chance := BASE_PASS_CHANCE / maxf(seg.overtaking_difficulty, 0.1)

	# Underlying pace difference (positive = attacker genuinely faster here).
	var pace_delta := (leader.segment_time - follower.segment_time) / maxf(leader.segment_time, 0.001)
	chance += pace_delta * PACE_DELTA_WEIGHT

	chance += (follower.driver.skill_overtaking - leader.driver.skill_defending) / 100.0 * SKILL_WEIGHT

	if seg.drs_zone and seg.type == TrackSegment.Type.STRAIGHT \
			and follower.gap_ahead_s < RaceEngine.SLIPSTREAM_GAP_S:
		chance += DRS_BONUS
	if follower.ers_mode == CarData.ErsMode.OVERTAKE and follower.ers_charge > 0.0:
		chance += ERS_ATTACK_BONUS
	if leader.ers_mode == CarData.ErsMode.OVERTAKE and leader.ers_charge > 0.0:
		chance -= ERS_DEFEND_MALUS

	return clampf(chance, MIN_CHANCE, MAX_CHANCE)
