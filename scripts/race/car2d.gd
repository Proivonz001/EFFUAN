class_name Car2D
extends Node2D
## Visual representation of one car. Pull-based: every frame it reads its
## CarData (written only by the engine) and eases toward the target curve
## offset. No signals, no sim writes.

# Top-down open-wheel silhouette (pointing +x): nose, cockpit bulge, sidepods.
static var BODY_POINTS := PackedVector2Array([
	16, 0, 12, -2, 6, -3, 2, -6, -6, -6, -10, -4, -12, -4, -12, 4, -10, 4, -6, 6, 2, 6, 6, 3, 12, 2])
static var FRONT_WING := PackedVector2Array([15, -8, 17, -8, 17, 8, 15, 8])
static var REAR_WING := PackedVector2Array([-15, -7, -12, -7, -12, 7, -15, 7])

const SMOOTHING := 9.0               # 1/s — how fast the visual chases the sim position
const LANE_BASE_PX := 5.0            # everyday side offset so cars don't stack
const LANE_BATTLE_PX := 13.0         # widened while attacking/defending
const TRAIL_LENGTH := 12
const DRS_COLOR := Color(0.2, 1.0, 0.5)
const ERS_COLOR := Color(1.0, 0.35, 0.9)

var car: CarData
var renderer: TrackRenderer

var _visual_offset := 0.0
var _lane_current := 0.0
var _lane_side := 1.0
var _body: Polygon2D
var _front_wing: Polygon2D
var _rear_wing: Polygon2D
var _cockpit: Polygon2D
var _ers_dot: Polygon2D
var _shadow: Polygon2D
var _glow: Node2D
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

	_shadow = Polygon2D.new()
	_shadow.polygon = BODY_POINTS
	_shadow.color = Color(0, 0, 0, 0.35)
	_shadow.position = Vector2(2.5, 3.5)
	add_child(_shadow)

	if car.is_player:
		_glow = Node2D.new()
		add_child(_glow)
		var ring := Line2D.new()
		var pts := PackedVector2Array()
		for i in 25:
			var a := TAU * i / 24.0
			pts.append(Vector2(cos(a), sin(a)) * 19.0)
		ring.points = pts
		ring.width = 2.0
		ring.default_color = Color(1, 1, 1, 0.55)
		_glow.add_child(ring)

	_body = Polygon2D.new()
	_body.polygon = BODY_POINTS
	_body.color = car.team.primary_color
	add_child(_body)

	_front_wing = Polygon2D.new()
	_front_wing.polygon = FRONT_WING
	_front_wing.color = car.team.primary_color.lightened(0.25)
	add_child(_front_wing)

	_rear_wing = Polygon2D.new()
	_rear_wing.polygon = REAR_WING
	_rear_wing.color = car.team.primary_color.darkened(0.25)
	add_child(_rear_wing)

	_cockpit = Polygon2D.new()
	_cockpit.polygon = PackedVector2Array([3, -2, 3, 2, -4, 2, -4, -2])
	_cockpit.color = Color(0.06, 0.06, 0.08)
	add_child(_cockpit)

	_ers_dot = Polygon2D.new()
	var dot := PackedVector2Array()
	for i in 9:
		var a := TAU * i / 8.0
		dot.append(Vector2(cos(a), sin(a)) * 3.0 + Vector2(-8, 0))
	_ers_dot.polygon = dot
	_ers_dot.color = ERS_COLOR
	_ers_dot.visible = false
	add_child(_ers_dot)

	# Driver code tag — counter-rotated child so it always reads horizontally.
	_tag = Node2D.new()
	add_child(_tag)
	_tag_label = Label.new()
	_tag_label.text = car.driver.code
	_tag_label.add_theme_font_size_override("font_size", 11)
	_tag_label.add_theme_color_override("font_color",
			Color.WHITE if car.is_player else Color(car.team.primary_color.lightened(0.35), 0.9))
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

	# Pit stop: park beside the start line instead of freezing on the racing line.
	if car.in_pit:
		var line_dir := renderer.direction_at(0.0)
		var line_perp := Vector2(-line_dir.y, line_dir.x)
		var slot := renderer.sample(fposmod(-70.0 - (car.index % 5) * 26.0, L)) \
				- line_perp * 34.0
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

	# Pit / retirement dimming.
	var dim := 1.0
	if car.in_pit:
		dim = 0.25
	elif car.dnf:
		dim = 0.15
	_body.color = Color(car.team.primary_color, dim)
	_front_wing.color = Color(car.team.primary_color.lightened(0.25), dim)
	_cockpit.color = Color(0.06, 0.06, 0.08, dim)
	_shadow.color = Color(0, 0, 0, 0.35 * dim)

	# DRS flap glows green when open; ERS dot pulses while deploying.
	if car.drs_open and not car.in_pit and not car.dnf:
		_rear_wing.color = DRS_COLOR
	else:
		_rear_wing.color = Color(car.team.primary_color.darkened(0.25), dim)
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
