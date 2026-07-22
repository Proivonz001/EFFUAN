class_name Car2D
extends Node2D
## Visual representation of one car. Pull-based: every frame it reads its
## CarData (written only by the engine) and eases toward the target curve
## offset. No signals, no sim writes.

const SMOOTHING := 9.0               # 1/s — how fast the visual chases the sim position
const LANE_BASE_PX := 5.0            # everyday side offset so cars don't stack
const LANE_BATTLE_PX := 13.0         # widened while attacking/defending — two-wide on the 34px ribbon
const TRAIL_LENGTH := 12
const DRS_COLOR := Color(0.2, 1.0, 0.5)
const ERS_COLOR := Color(1.0, 0.35, 0.9)
const CAR_SCALE := 0.42              # SVG is 64px long -> ~27px on track

static var LIVERY_TEX: Texture2D = preload("res://assets/cars/car_livery.svg")
static var DETAILS_TEX: Texture2D = preload("res://assets/cars/car_details.svg")

var car: CarData
var renderer: TrackRenderer
## True while the field is formed up pre-start: the car sits exactly on its
## painted grid box. Released by RaceManager when the lights go out.
var grid_hold := false

var _visual_offset := 0.0
var _lane_current := 0.0
var _lane_side := 1.0
var _gfx: Node2D                     # sprite stack, dimmed as a whole in pit/DNF
var _livery: Sprite2D
var _drs_flap: Polygon2D
var _ers_dot: Polygon2D
var _shadow: Sprite2D
var _trail: Line2D
var _tag: Node2D
var _tag_label: Label


func setup(p_car: CarData, p_renderer: TrackRenderer) -> void:
	car = p_car
	renderer = p_renderer
	_lane_side = 1.0 if (car.index % 2 == 0) else -1.0

	_trail = Line2D.new()
	_trail.width = 3.0
	_trail.top_level = true
	var grad := Gradient.new()
	# Points are newest-first, so the line starts opaque and fades toward the tail.
	grad.set_color(0, Color(car.team.primary_color, 0.4))
	grad.set_color(1, Color(car.team.primary_color, 0.0))
	_trail.gradient = grad
	add_child(_trail)

	# Sprite stack: shadow -> tinted livery -> neutral details -> indicators.
	_gfx = Node2D.new()
	_gfx.scale = Vector2(CAR_SCALE, CAR_SCALE)
	add_child(_gfx)

	_shadow = Sprite2D.new()
	_shadow.texture = LIVERY_TEX
	_shadow.self_modulate = Color(0, 0, 0, 0.4)
	_shadow.position = Vector2(4.0, 6.0)
	_gfx.add_child(_shadow)

	_livery = Sprite2D.new()
	_livery.texture = LIVERY_TEX
	_livery.self_modulate = car.team.primary_color
	_gfx.add_child(_livery)

	var details := Sprite2D.new()
	details.texture = DETAILS_TEX
	_gfx.add_child(details)

	# DRS flap overlay on the rear wing (glows green when open).
	_drs_flap = Polygon2D.new()
	_drs_flap.polygon = PackedVector2Array([-31, -11.5, -25, -11.5, -25, 11.5, -31, 11.5])
	_drs_flap.color = Color(DRS_COLOR, 0.85)
	_drs_flap.visible = false
	_gfx.add_child(_drs_flap)

	# ERS deploy indicator: exhaust glow behind the rear wing.
	_ers_dot = Polygon2D.new()
	var dot := PackedVector2Array()
	for i in 9:
		var a := TAU * i / 8.0
		dot.append(Vector2(cos(a) * 5.0, sin(a) * 3.2) + Vector2(-36, 0))
	_ers_dot.polygon = dot
	_ers_dot.color = ERS_COLOR
	_ers_dot.visible = false
	_gfx.add_child(_ers_dot)

	# Driver code tag — counter-rotated child so it always reads horizontally.
	# The player's cars are identified by their gold, larger tag.
	_tag = Node2D.new()
	add_child(_tag)
	_tag_label = Label.new()
	_tag_label.text = car.driver.code
	_tag_label.add_theme_font_size_override("font_size", 13 if car.is_player else 11)
	_tag_label.add_theme_color_override("font_color",
			Color(1.0, 0.84, 0.3) if car.is_player else Color(car.team.primary_color.lightened(0.35), 0.9))
	_tag_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_tag_label.add_theme_constant_override("shadow_offset_x", 1)
	_tag_label.add_theme_constant_override("shadow_offset_y", 1)
	_tag_label.position = Vector2(-12, -34)
	_tag.add_child(_tag_label)

	_visual_offset = _target_offset()
	_apply_transform(0.0)


func _process(delta: float) -> void:
	if car == null or renderer == null:
		return
	_apply_transform(delta)


func _target_offset() -> float:
	# Segment-anchored mapping: the car is exactly where its sim segment is drawn.
	return renderer.segment_offset(car.segment_index, car.segment_progress)


func _apply_transform(delta: float) -> void:
	var L := renderer.baked_length()

	# Formation: sit exactly on the painted grid box until lights out.
	# The grid camera is zoomed in, so every code tag stays readable.
	if grid_hold:
		var slot := TrackRenderer.grid_slot_transform(car.grid_pos)
		var off: float = fposmod(slot.offset, L)
		var p := renderer.sample(off)
		var dir := renderer.direction_at(off)
		var perp := Vector2(-dir.y, dir.x)
		position = p + perp * slot.lane
		rotation = dir.angle()
		_visual_offset = off
		return

	# Pit stop: park beside the start line instead of freezing on the racing line.
	if car.in_pit:
		var line_dir := renderer.direction_at(0.0)
		var line_perp := Vector2(-line_dir.y, line_dir.x)
		var slot := renderer.sample(fposmod(-70.0 - (car.index % 5) * 26.0, L)) \
				- line_perp * TrackRenderer.PIT_LANE_DEPTH
		position = position.lerp(slot, minf(delta * 6.0, 1.0))
		_visual_offset = fposmod(-70.0, L)
		return

	var target := _target_offset()
	# Shortest-path circular lerp so the s/f wrap doesn't snap the car backward.
	var diff := fposmod(target - _visual_offset + L * 0.5, L) - L * 0.5
	# The train clamp nudges the sim position backward a few meters every tick;
	# chasing those nudges reads as stop-and-go stutter. Hold instead, and let
	# the forward motion of the next ticks re-absorb the offset.
	if diff < 0.0 and diff > -60.0:
		diff = 0.0
	_visual_offset = fposmod(_visual_offset + diff * minf(delta * SMOOTHING, 1.0), L)

	var lane_target := (LANE_BATTLE_PX if car.in_battle else LANE_BASE_PX) * _lane_side
	_lane_current = lerpf(_lane_current, lane_target, minf(delta * 4.0, 1.0))

	var pos := renderer.sample(_visual_offset)
	var dir := renderer.direction_at(_visual_offset)
	var perp := Vector2(-dir.y, dir.x)
	position = pos + perp * _lane_current
	rotation = dir.angle()

	# Pit / retirement dimming (whole sprite stack at once).
	var dim := 1.0
	if car.in_pit:
		dim = 0.3
	elif car.dnf:
		dim = 0.15
	_gfx.modulate = Color(1, 1, 1, dim)

	# DRS flap glows green when open; ERS exhaust pulses while deploying.
	_drs_flap.visible = car.drs_open and not car.in_pit and not car.dnf
	var deploying: bool = (car.ers_mode == CarData.ErsMode.DEPLOY
			or car.ers_mode == CarData.ErsMode.OVERTAKE) and car.ers_charge > 0.0
	_ers_dot.visible = deploying and not car.in_pit and not car.dnf
	if _ers_dot.visible:
		_ers_dot.color = Color(ERS_COLOR, 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.02))

	# Keep the code tag horizontal and readable.
	if _tag:
		_tag.rotation = -rotation
		_tag.visible = not car.dnf
		_tag_label.modulate = Color(1, 1, 1, 0.45 if car.in_pit else 1.0)

	# Trail (world-space points, newest first).
	if _trail:
		var pts := _trail.points
		pts.insert(0, position)
		if pts.size() > TRAIL_LENGTH:
			pts.resize(TRAIL_LENGTH)
		_trail.points = pts
		_trail.visible = not car.in_pit and not car.dnf
