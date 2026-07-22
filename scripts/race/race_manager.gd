class_name RaceManager
extends Node2D
## Owns the RaceEngine instance and is the ONLY object that talks to it.
## Advances the sim at a fixed 20Hz tick scaled by time_scale, re-emits engine
## events as signals, and exposes command methods for the pit wall UI.

signal positions_changed(order: Array)
signal lap_completed(car: CarData, lap: int, time: float)
signal overtake_happened(attacker: CarData, defender: CarData)
signal pit_event(car: CarData, entering: bool)
signal race_finished(classification: Array)
signal leader_lap_changed(lap: int, total: int)

const SIM_TICK := 0.05
const TIME_SCALES: Array[float] = [1.0, 4.0, 8.0]

var engine := RaceEngine.new()
var time_scale_index := 2
var race_running := false

var _accumulator := 0.0
var _track_data: TrackData
var _renderer: TrackRenderer
var _car_nodes: Array = []
var _last_leader_lap := 0
var _positions_timer := 0.0


# Children (UI panels) read the engine in their _ready, which runs BEFORE the
# parent's _ready — so the race must be assembled in _enter_tree.
func _enter_tree() -> void:
	_setup_race()


func _setup_race() -> void:
	var series: SeriesData = GameData.get_current_series()
	_track_data = GameData.get_current_track()
	if series == null or _track_data == null:
		push_error("RaceManager: missing series or track data")
		return

	# Track scene.
	var track_scene: Node2D = load(_track_data.scene_path).instantiate()
	add_child(track_scene)
	move_child(track_scene, 0)
	_renderer = track_scene.get_node("TrackRenderer")

	# Engine.
	var compounds: Array = []
	for cid in series.allowed_compound_ids:
		compounds.append(GameData.get_compound(cid))
	var entries: Array = GameData.build_entries(series)
	engine.setup(_track_data, entries, series.race_laps, compounds, GameData.player_team_id)

	# Car visuals.
	var car_layer := Node2D.new()
	car_layer.name = "CarLayer"
	add_child(car_layer)
	for car in engine.cars:
		var node := Car2D.new()
		car_layer.add_child(node)
		node.setup(car, _renderer)
		_car_nodes.append(node)

	race_running = true
	leader_lap_changed.emit(1, engine.race_laps)
	positions_changed.emit(engine.get_classification())


func _physics_process(delta: float) -> void:
	if not race_running:
		return
	_accumulator += delta
	while _accumulator >= SIM_TICK:
		_accumulator -= SIM_TICK
		engine.tick(SIM_TICK * TIME_SCALES[time_scale_index])
		_drain_events()

	_positions_timer += delta
	if _positions_timer >= 0.25:
		_positions_timer = 0.0
		positions_changed.emit(engine.get_classification())
		var leader: CarData = engine.get_classification()[0]
		if leader.lap != _last_leader_lap:
			_last_leader_lap = leader.lap
			leader_lap_changed.emit(leader.lap, engine.race_laps)


func _drain_events() -> void:
	for ev in engine.events:
		match ev.type:
			"lap":
				lap_completed.emit(ev.car, ev.lap, ev.time)
			"overtake":
				overtake_happened.emit(ev.attacker, ev.defender)
			"pit_in":
				pit_event.emit(ev.car, true)
			"pit_out":
				pit_event.emit(ev.car, false)
			"race_finished":
				race_running = false
				race_finished.emit(engine.get_classification())
	engine.events.clear()


# ------------------------------------------------------------ UI commands ---

func set_time_scale(index: int) -> void:
	time_scale_index = clampi(index, 0, TIME_SCALES.size() - 1)


func player_cars() -> Array:
	var out: Array = []
	for car in engine.cars:
		if car.is_player:
			out.append(car)
	return out


func cmd_set_ers(car: CarData, mode: int) -> void:
	engine.set_ers_mode(car.index, mode)


func cmd_set_mix(car: CarData, mix: int) -> void:
	engine.set_fuel_mix(car.index, mix)


func cmd_toggle_pit(car: CarData, compound: TyreCompound) -> void:
	if car.pit_requested:
		engine.cancel_pit(car.index)
	else:
		engine.request_pit(car.index, compound)
