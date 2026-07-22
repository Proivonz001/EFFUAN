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
signal fastest_lap_set(car: CarData, time: float)
signal replay_ready(data: Dictionary)

const SIM_TICK := 0.05
const TIME_SCALES: Array[float] = [1.0, 4.0, 8.0]

var engine := RaceEngine.new()
var time_scale_index := 1            # default 4x: 8x proved too fast to make calls
var race_running := false
var paused := true                   # races start paused behind a START button

const CAMERA_MODES := ["FULL", "TV", "CAR"]

var camera_mode := 0

var _accumulator := 0.0
var _track_data: TrackData
var _renderer: TrackRenderer
var _car_nodes: Array = []
var _last_leader_lap := 0
var _positions_timer := 0.0
var _rain: CPUParticles2D
var _camera: Camera2D
var _cam_battle: Array = []          # the two CarData currently framed by TV mode
var _cam_battle_timer := 0.0
var _session_fl := 1e9
var _replay_frames: Array = []       # ring buffer: {p: PackedVector2Array, r: PackedFloat32Array}
var _replay_timer := 0.0
var _last_replay_ms := -100000


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

	_build_backdrop()

	# Track scene.
	var track_scene: Node2D = load(_track_data.scene_path).instantiate()
	add_child(track_scene)
	move_child(track_scene, 0)
	_renderer = track_scene.get_node("TrackRenderer")
	_build_rain()

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

	# Broadcast camera + battle highlight overlay.
	_camera = Camera2D.new()
	_camera.position = Vector2(960, 540)
	add_child(_camera)
	_camera.make_current()
	var battles := BattleOverlay.new()
	battles.manager = self
	battles.z_index = 5
	add_child(battles)

	race_running = true
	if "--cam-car" in OS.get_cmdline_user_args():
		camera_mode = 2   # debug: boot straight into the chase camera
	if "--autostart" in OS.get_cmdline_user_args():
		paused = false
	else:
		_build_start_overlay.call_deferred()
	leader_lap_changed.emit(1, engine.race_laps)
	positions_changed.emit(engine.get_classification())


## Soft radial vignette + dot grid behind everything — kills the flat black.
func _build_backdrop() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.6, 1.0));
	vec3 base = vec3(0.075, 0.082, 0.104);
	vec3 edge = vec3(0.034, 0.038, 0.052);
	vec3 col = mix(base, edge, smoothstep(0.2, 0.85, d));
	vec2 g = fract(FRAGCOORD.xy / 48.0) - 0.5;
	col += smoothstep(0.07, 0.02, length(g)) * 0.014;
	COLOR = vec4(col, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	layer.add_child(rect)


func _build_rain() -> void:
	_rain = CPUParticles2D.new()
	_rain.emitting = false
	_rain.amount = 260
	_rain.lifetime = 0.9
	_rain.position = Vector2(960, 380)
	_rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_rain.emission_rect_extents = Vector2(1100, 620)
	_rain.direction = Vector2(0.12, 1.0)
	_rain.spread = 4.0
	_rain.initial_velocity_min = 700.0
	_rain.initial_velocity_max = 950.0
	_rain.gravity = Vector2(0, 300)
	var streak := GradientTexture2D.new()
	streak.width = 2
	streak.height = 14
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.set_color(1, Color(0.7, 0.8, 1.0, 0.6))
	streak.gradient = grad
	streak.fill_from = Vector2(0.5, 0.0)
	streak.fill_to = Vector2(0.5, 1.0)
	_rain.texture = streak
	_rain.z_index = 20
	add_child(_rain)


func _sync_weather_visuals() -> void:
	var w: WeatherSystem = engine.weather
	if _renderer:
		_renderer.wetness = w.wetness
	if _rain:
		_rain.emitting = w.intensity > 0.05
		_rain.modulate = Color(1, 1, 1, clampf(0.25 + w.intensity, 0.0, 1.0))
		if _camera:
			# Keep the rain sheet over the camera view at any zoom.
			_rain.position = _camera.position - Vector2(0, 160.0 / _camera.zoom.x)
			_rain.emission_rect_extents = Vector2(1100, 620) / _camera.zoom.x
	Sfx.set_ambient_pitch(0.8 + 0.15 * time_scale_index)


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
		start.visible = false
		_run_start_lights(overlay, vbox))
	vbox.add_child(start)


## Five red lights... and it's lights out.
func _run_start_lights(overlay: Node, vbox: VBoxContainer) -> void:
	var lights_row := HBoxContainer.new()
	lights_row.add_theme_constant_override("separation", 14)
	lights_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(lights_row)
	var lights: Array = []
	for i in 5:
		var light := Panel.new()
		light.custom_minimum_size = Vector2(46, 46)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.05, 0.05)
		sb.set_corner_radius_all(23)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.3, 0.3, 0.34)
		light.add_theme_stylebox_override("panel", sb)
		lights_row.add_child(light)
		lights.append(sb)
	for sb in lights:
		await get_tree().create_timer(0.55).timeout
		if not is_instance_valid(overlay):
			return   # player skipped with SPACE
		sb.bg_color = Color(0.95, 0.12, 0.10)
		Sfx.light_on()
	await get_tree().create_timer(randf_range(0.5, 1.3)).timeout
	if not is_instance_valid(overlay):
		return
	Sfx.lights_out()
	Sfx.start_ambient()
	paused = false
	overlay.queue_free()


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
		KEY_C:
			cycle_camera()


func _process(delta: float) -> void:
	_update_camera(delta)
	if race_running and not paused:
		_record_replay_frame(delta)


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
		_sync_weather_visuals()
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
				if ev.time < _session_fl:
					_session_fl = ev.time
					fastest_lap_set.emit(ev.car, ev.time)
			"overtake":
				overtake_happened.emit(ev.attacker, ev.defender)
				_maybe_replay(ev.attacker, ev.defender)
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
				Sfx.stop_ambient()
				race_finished.emit(engine.get_classification())
	engine.events.clear()


func _exit_tree() -> void:
	Sfx.stop_ambient()


# ------------------------------------------------------------ UI commands ---

func set_time_scale(index: int) -> void:
	time_scale_index = clampi(index, 0, TIME_SCALES.size() - 1)


func toggle_pause() -> void:
	var overlay := get_node_or_null("UI/StartOverlay")
	if overlay:
		overlay.queue_free()
	paused = not paused


func cycle_camera() -> void:
	camera_mode = (camera_mode + 1) % CAMERA_MODES.size()


func car_node(index: int) -> Car2D:
	return _car_nodes[index]


# ---------------------------------------------------------- broadcast camera -

func _update_camera(delta: float) -> void:
	if _camera == null:
		return
	var target := Vector2(960, 540)
	var zoom := 1.0
	match camera_mode:
		1:   # TV: frame the most interesting battle, sticky for a few seconds.
			_cam_battle_timer -= delta
			if _cam_battle_timer <= 0.0 or not _battle_still_valid():
				_cam_battle = _pick_battle()
				_cam_battle_timer = 3.0
			if _cam_battle.size() == 2:
				var a := car_node(_cam_battle[0].index)
				var b := car_node(_cam_battle[1].index)
				target = (a.position + b.position) * 0.5
				zoom = 1.9
			elif not engine.order.is_empty():
				target = car_node(engine.order[0].index).position
				zoom = 1.9
		2:   # CAR: chase the player's lead car.
			var players := player_cars()
			if not players.is_empty():
				target = car_node(players[0].index).position
				zoom = 2.1
	_camera.position = _camera.position.lerp(target, minf(delta * 3.0, 1.0))
	var z := _camera.zoom.x + (zoom - _camera.zoom.x) * minf(delta * 2.5, 1.0)
	_camera.zoom = Vector2(z, z)


func _battle_still_valid() -> bool:
	if _cam_battle.size() != 2:
		return false
	for car in _cam_battle:
		if car.finished or car.dnf or car.in_pit:
			return false
	return _cam_battle[1].gap_ahead_s < 1.6


func _pick_battle() -> Array:
	var best: Array = []
	var best_score := -1e9
	var order: Array = engine.order
	for i in range(1, order.size()):
		var lead: CarData = order[i - 1]
		var chase: CarData = order[i]
		if lead.finished or chase.finished or lead.dnf or chase.dnf \
				or lead.in_pit or chase.in_pit or chase.gap_ahead_s > 1.2:
			continue
		var score := 20.0 - i - chase.gap_ahead_s * 4.0
		if lead.is_player or chase.is_player:
			score += 6.0
		if score > best_score:
			best_score = score
			best = [lead, chase]
	return best


# ------------------------------------------------------------ replay capture -

func _record_replay_frame(delta: float) -> void:
	_replay_timer += delta
	if _replay_timer < 0.1:
		return
	_replay_timer = 0.0
	var pos := PackedVector2Array()
	var rot := PackedFloat32Array()
	for node: Car2D in _car_nodes:
		pos.append(node.position)
		rot.append(node.rotation)
	_replay_frames.append({"p": pos, "r": rot})
	while _replay_frames.size() > 55:
		_replay_frames.pop_front()


## A top-6 or player overtake triggers the mini replay (with a cooldown).
func _maybe_replay(attacker: CarData, defender: CarData) -> void:
	var notable: bool = attacker.is_player or defender.is_player \
			or engine.order.find(attacker) <= 5
	var now := Time.get_ticks_msec()
	if not notable or now - _last_replay_ms < 25000 or _replay_frames.size() < 25:
		return
	_last_replay_ms = now
	var frames: Array = []
	for f in _replay_frames:
		frames.append({
			"a": f.p[attacker.index], "ar": f.r[attacker.index],
			"b": f.p[defender.index], "br": f.r[defender.index],
		})
	# Local track geometry inside the action's bounding box.
	var bbox := Rect2(frames[0].a, Vector2.ZERO)
	for f in frames:
		bbox = bbox.expand(f.a).expand(f.b)
	bbox = bbox.grow(70.0)
	var chunks: Array = []
	var run := PackedVector2Array()
	for p in _renderer._baked:
		if bbox.has_point(p):
			run.append(p)
		elif run.size() > 1:
			chunks.append(run)
			run = PackedVector2Array()
		else:
			run = PackedVector2Array()
	if run.size() > 1:
		chunks.append(run)
	replay_ready.emit({
		"frames": frames, "bbox": bbox, "chunks": chunks,
		"code_a": attacker.short_code(), "code_b": defender.short_code(),
		"col_a": attacker.team.primary_color, "col_b": defender.team.primary_color,
	})


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
