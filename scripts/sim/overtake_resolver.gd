class_name OvertakeResolver
extends RefCounted
## Battle resolution between adjacent cars on track. Called once per engine tick,
## after the position sort. Two outcomes when a car catches the one ahead:
## a clean swap, or the train clamp (held behind at MIN_GAP, inheriting the pace).

# ------------------------------------------------------------------ tuning ---
const BASE_PASS_CHANCE := 0.13        # divided by the zone's overtaking_difficulty
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
		if leader.finished or follower.finished or leader.in_pit or follower.in_pit:
			follower.in_battle = false
			continue
		_resolve_pair(engine, leader, follower)


static func _resolve_pair(engine: RaceEngine, leader: CarData, follower: CarData) -> void:
	var min_gap_m: float = RaceEngine.MIN_GAP_S * maxf(leader.current_speed, 1.0)
	var caught: bool = follower.race_distance_m > leader.race_distance_m - min_gap_m
	if not caught:
		follower.in_battle = false
		return

	follower.in_battle = true
	leader.in_battle = true

	if follower.attack_cooldown == 0:
		var chance := _pass_chance(engine, leader, follower)
		follower.attack_cooldown = RaceEngine.ATTACK_COOLDOWN_SEGMENTS
		if engine.rng().randf() < chance:
			# Clean swap: attacker emerges just ahead, defender loses momentum.
			# The defender also gets a cooldown so the pair doesn't ping-pong.
			engine.set_race_distance(follower, leader.race_distance_m + SWAP_LEAD_M)
			leader.segment_time *= DEFENDER_TIME_LOSS
			leader.attack_cooldown = RaceEngine.ATTACK_COOLDOWN_SEGMENTS + 2
			engine.events.append({
				"type": "overtake", "attacker": follower, "defender": leader,
				"lap": maxi(follower.lap, 1),
			})
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
