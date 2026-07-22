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
signal dnf_happened(car: CarData)
signal sc_changed(phase: String)

const SIM_TICK := 0.05
const TIME_SCALES: Array[float] = [1.0, 4.0, 8.0]

var engine := RaceEngine.new()
var time_scale_index := 1            # default 4x: 8x proved too fast to make calls
var race_running := false
var paused := true                   # races start paused behind a START button

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


# Runs after every child is ready: push the initial grid to the UI, since the
# race starts paused and the periodic updates only flow once it's running.
func _ready() -> void:
	positions_changed.emit(engine.get_classification())
	leader_lap_changed.emit(1, engine.race_laps)


func _setup_race() -> void:
	var series: SeriesData
	var entries: Array
	var weather: WeatherSystem = null
	var grid_ready := false
	if GameState.career_active:
		series = GameState.player_series()
		_track_data = GameState.current_track()
		weather = GameState.pending_weather
		if GameState.pending_grid.is_empty():
			entries = GameState.build_entries(GameState.player_series_id)
		else:
			entries = GameState.pending_grid
			grid_ready = true
	else:
		# No career context (direct race.tscn run / tests): quick exhibition race.
		series = GameData.get_current_series()
		_track_data = GameData.get_current_track()
		entries = GameData.build_entries(series)
	if series == null or _track_data == null:
		push_error("RaceManager: missing series or track data")
		return

	# Track scene.
	var track_scene: Node2D = load(_track_data.scene_path).instantiate()
	add_child(track_scene)
	move_child(track_scene, 0)
	_renderer = track_scene.get_node("TrackRenderer")

	# Engine. Rain compounds are always in the pool alongside the series slicks.
	var compounds: Array = []
	for cid in series.allowed_compound_ids:
		compounds.append(GameData.get_compound(cid))
	for cid in ["inter", "wet"]:
		var c := GameData.get_compound(cid)
		if c and c not in compounds:
			compounds.append(c)
	var seed_value: int = GameState.race_seed() if GameState.career_active else 0
	engine.setup(_track_data, entries, series.race_laps, compounds,
			GameData.player_team_id, seed_value, weather, grid_ready)

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
	if "--autostart" in OS.get_cmdline_user_args():
		paused = false
	else:
		_build_start_overlay.call_deferred()
	leader_lap_changed.emit(1, engine.race_laps)
	positions_changed.emit(engine.get_classification())


func _build_start_overlay() -> void:
	var overlay := CenterContainer.new()
	overlay.name = "StartOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_node("UI").add_child(overlay)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	overlay.add_child(vbox)
	var info := Label.new()
	info.text = "%s  —  %d LAPS" % [_track_data.track_name.to_upper(), engine.race_laps]
	info.add_theme_font_size_override("font_size", 22)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	var hint := Label.new()
	hint.text = "SPACE pauses any time  ·  keys 1 / 2 / 3 set speed"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	var start := Button.new()
	start.text = "START RACE"
	start.custom_minimum_size = Vector2(280, 60)
	start.add_theme_font_size_override("font_size", 22)
	start.focus_mode = Control.FOCUS_NONE
	start.pressed.connect(func() -> void:
		paused = false
		overlay.queue_free())
	vbox.add_child(start)


func _unhandled_key_input(event: InputEvent) -> void:
	if not race_running or event.is_echo() or not event.is_pressed():
		return
	match event.keycode:
		KEY_SPACE:
			var overlay := get_node_or_null("UI/StartOverlay")
			if overlay:
				overlay.queue_free()
			paused = not paused
		KEY_1:
			set_time_scale(0)
		KEY_2:
			set_time_scale(1)
		KEY_3:
			set_time_scale(2)


func _physics_process(delta: float) -> void:
	if not race_running or paused:
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
			"dnf":
				dnf_happened.emit(ev.car)
			"sc":
				sc_changed.emit(ev.phase)
			"race_finished":
				race_running = false
				race_finished.emit(engine.get_classification())
	engine.events.clear()


# ------------------------------------------------------------ UI commands ---

func set_time_scale(index: int) -> void:
	time_scale_index = clampi(index, 0, TIME_SCALES.size() - 1)


func toggle_pause() -> void:
	var overlay := get_node_or_null("UI/StartOverlay")
	if overlay:
		overlay.queue_free()
	paused = not paused


## Live gaps for the selected car's pit-wall readout: [ahead_s, behind_s] (-1 = none).
func gaps_around(car: CarData) -> Array:
	var idx := engine.order.find(car)
	var ahead := -1.0
	var behind := -1.0
	if idx > 0:
		ahead = car.gap_ahead_s
	if idx >= 0 and idx < engine.order.size() - 1:
		behind = engine.order[idx + 1].gap_ahead_s
	return [ahead, behind]


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
