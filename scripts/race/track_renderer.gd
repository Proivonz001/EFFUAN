@tool
class_name TrackRenderer
extends Node2D
## Draws the circuit from the baked TrackPath curve: asphalt ribbon, edge lines,
## DRS zones, start/finish line. In the editor it also tints the centerline per
## segment (green straights / orange corners / blue DRS) to spot curve-vs-data
## misalignment at a glance.

const ASPHALT := Color(0.165, 0.175, 0.20)
const EDGE := Color(0.85, 0.86, 0.88, 0.9)
const DRS_COLOR := Color(0.15, 0.9, 0.45, 0.85)
const TRACK_WIDTH := 34.0

@export var path: TrackPath
@export var track_data: TrackData

var _baked: PackedVector2Array = []
var _baked_len: float = 0.0


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	if path == null or path.curve == null:
		return
	_baked = path.curve.get_baked_points()
	_baked_len = path.curve.get_baked_length()
	queue_redraw()


func baked_length() -> float:
	if _baked_len <= 0.0:
		_refresh()
	return _baked_len


## Map a normalized lap fraction [0..1] to a curve offset in pixels.
func lap_fraction_to_offset(f: float) -> float:
	return fposmod(f, 1.0) * baked_length()


func sample(offset_px: float) -> Vector2:
	return path.curve.sample_baked(fposmod(offset_px, _baked_len))


func direction_at(offset_px: float) -> Vector2:
	var a := sample(offset_px)
	var b := sample(offset_px + 4.0)
	return (b - a).normalized()


func _draw() -> void:
	if _baked.is_empty():
		_refresh()
		if _baked.is_empty():
			return
	var closed := _baked.duplicate()
	closed.append(_baked[0])

	# Ribbon: edge underlay then asphalt on top.
	draw_polyline(closed, EDGE, TRACK_WIDTH + 5.0, true)
	draw_polyline(closed, ASPHALT, TRACK_WIDTH, true)

	if track_data:
		_draw_zones()
	_draw_start_line()
	if Engine.is_editor_hint() and track_data:
		_draw_segment_tints()


## DRS zones as a thin stripe along the edge of the ribbon, off the racing line.
func _draw_zones() -> void:
	var total := track_data.total_length_m()
	for i in track_data.segment_count():
		var seg := track_data.get_segment(i)
		if not seg.drs_zone:
			continue
		var f0 := track_data.cum_length_m(i) / total
		var f1 := f0 + seg.length_m / total
		var pts := _points_between(f0, f1)
		if pts.size() < 2:
			continue
		var edge_pts := PackedVector2Array()
		for j in pts.size():
			var dir := (pts[mini(j + 1, pts.size() - 1)] - pts[maxi(j - 1, 0)]).normalized()
			edge_pts.append(pts[j] + Vector2(-dir.y, dir.x) * (TRACK_WIDTH * 0.5 + 5.0))
		draw_polyline(edge_pts, Color(DRS_COLOR, 0.6), 3.0)


func _draw_start_line() -> void:
	var p := sample(0.0)
	var dir := direction_at(0.0)
	var perp := Vector2(-dir.y, dir.x)
	var half := TRACK_WIDTH * 0.5
	# Checkered-ish double bar.
	draw_line(p - perp * half, p + perp * half, Color.WHITE, 6.0)
	draw_line(p - perp * half + dir * 7.0, p + perp * half + dir * 7.0, Color(1, 1, 1, 0.35), 3.0)


func _draw_segment_tints() -> void:
	var total := track_data.total_length_m()
	for i in track_data.segment_count():
		var seg := track_data.get_segment(i)
		var f0 := track_data.cum_length_m(i) / total
		var f1 := f0 + seg.length_m / total
		var pts := _points_between(f0, f1)
		if pts.size() < 2:
			continue
		var col := Color(0.3, 0.9, 0.3, 0.8)
		if seg.type == TrackSegment.Type.CORNER:
			col = [Color(0.95, 0.35, 0.2, 0.8), Color(0.95, 0.6, 0.2, 0.8), Color(0.95, 0.8, 0.3, 0.8)][seg.corner_class - 1]
		draw_polyline(pts, col, 3.0)
		draw_circle(pts[0], 5.0, Color.WHITE)


func _points_between(f0: float, f1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := maxi(int((f1 - f0) * 80.0), 2)
	for s in steps + 1:
		var f := lerpf(f0, f1, float(s) / steps)
		pts.append(sample(f * _baked_len))
	return pts
