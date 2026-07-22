class_name Car2D
extends Node2D
## Visual representation of one car. Pull-based: every frame it reads its
## CarData (written only by the engine) and eases toward the target curve
## offset. No signals, no sim writes.

static var BODY_POINTS := PackedVector2Array([14, 0, 7, -5, -9, -5, -13, -3, -13, 3, -9, 5, 7, 5])
const SMOOTHING := 9.0               # 1/s — how fast the visual chases the sim position
const LANE_BASE_PX := 5.0            # everyday side offset so cars don't stack
const LANE_BATTLE_PX := 13.0         # widened while attacking/defending
const TRAIL_LENGTH := 12

var car: CarData
var renderer: TrackRenderer

var _visual_offset := 0.0
var _lane_current := 0.0
var _lane_side := 1.0
var _body: Polygon2D
var _shadow: Polygon2D
var _glow: Node2D
var _trail: Line2D


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

	_visual_offset = _target_offset()
	_apply_transform(0.0)


func _process(delta: float) -> void:
	if car == null or renderer == null:
		return
	_apply_transform(delta)


func _target_offset() -> float:
	var total := car.race_distance_m
	var track := renderer.track_data
	var lap_fraction := fposmod(total, track.total_length_m()) / track.total_length_m()
	return renderer.lap_fraction_to_offset(lap_fraction)


func _apply_transform(delta: float) -> void:
	var L := renderer.baked_length()
	var target := _target_offset()
	# Shortest-path circular lerp so the s/f wrap doesn't snap the car backward.
	var diff := fposmod(target - _visual_offset + L * 0.5, L) - L * 0.5
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
	_shadow.color = Color(0, 0, 0, 0.35 * dim)

	# Trail (world-space points, newest first).
	if _trail:
		var pts := _trail.points
		pts.insert(0, position)
		if pts.size() > TRAIL_LENGTH:
			pts.resize(TRAIL_LENGTH)
		_trail.points = pts
		_trail.visible = not car.in_pit and not car.dnf
