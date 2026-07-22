@tool
class_name TrackRenderer
extends Node2D
## Draws the circuit from the baked TrackPath curve: asphalt ribbon, edge lines,
## DRS zones, start/finish line. In the editor it also tints the centerline per
## segment (green straights / orange corners / blue DRS) to spot curve-vs-data
## misalignment at a glance.

const ASPHALT := Color(0.165, 0.175, 0.20)
const ASPHALT_WET := Color(0.09, 0.10, 0.135)
const EDGE := Color(0.85, 0.86, 0.88, 0.9)
const DRS_COLOR := Color(0.15, 0.9, 0.45, 0.85)
const KERB_RED := Color(0.82, 0.18, 0.16)
const KERB_WHITE := Color(0.88, 0.88, 0.9)
const TRACK_WIDTH := 34.0
const KERB_DASH_PX := 14.0

@export var path: TrackPath
@export var track_data: TrackData

## Live track wetness [0..1] — RaceManager pushes it; darkens the asphalt.
var wetness := 0.0:
	set(value):
		if absf(value - wetness) > 0.02:
			wetness = value
			queue_redraw()
		else:
			wetness = value

var _baked: PackedVector2Array = []
var _baked_len: float = 0.0
var _label_font: Font


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

	# Ribbon: edge underlay then asphalt on top; rain darkens the surface.
	draw_polyline(closed, EDGE, TRACK_WIDTH + 5.0, true)
	draw_polyline(closed, ASPHALT.lerp(ASPHALT_WET, wetness), TRACK_WIDTH, true)

	if track_data:
		_draw_kerbs()
		_draw_zones()
	_draw_start_line()
	if Engine.is_editor_hint() and track_data:
		_draw_segment_tints()


## Red/white dashes along both edges of every corner.
func _draw_kerbs() -> void:
	var total := track_data.total_length_m()
	for i in track_data.segment_count():
		var seg := track_data.get_segment(i)
		if seg.type != TrackSegment.Type.CORNER:
			continue
		var f0 := track_data.cum_length_m(i) / total
		var f1 := f0 + seg.length_m / total
		var span_px := (f1 - f0) * _baked_len
		var dashes := maxi(int(span_px / KERB_DASH_PX), 2)
		for d in dashes:
			var fa := lerpf(f0, f1, float(d) / dashes)
			var fb := lerpf(f0, f1, (d + 0.82) / dashes)
			var pa := sample(fa * _baked_len)
			var pb := sample(fb * _baked_len)
			var dir := (pb - pa).normalized()
			var perp := Vector2(-dir.y, dir.x)
			var col := KERB_RED if d % 2 == 0 else KERB_WHITE
			var off := TRACK_WIDTH * 0.5 + 3.5
			draw_line(pa + perp * off, pb + perp * off, col, 4.5)
			draw_line(pa - perp * off, pb - perp * off, col, 4.5)


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
		# Zone label at the detection point.
		if _label_font == null:
			_label_font = ThemeDB.fallback_font
		var lp := edge_pts[mini(2, edge_pts.size() - 1)]
		draw_string(_label_font, lp + Vector2(-12, -8), "DRS",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(DRS_COLOR, 0.9))


func _draw_start_line() -> void:
	var p := sample(0.0)
	var dir := direction_at(0.0)
	var perp := Vector2(-dir.y, dir.x)
	var half := TRACK_WIDTH * 0.5
	# Proper checkered strip: 2 rows x N cells across the track.
	var cells := 8
	var cell := half * 2.0 / cells
	for row in 2:
		for c in cells:
			var col := Color(0.92, 0.92, 0.94) if (row + c) % 2 == 0 else Color(0.1, 0.1, 0.12)
			var origin := p - perp * half + perp * (c * cell) + dir * (row * cell)
			draw_colored_polygon(PackedVector2Array([
				origin, origin + perp * cell, origin + perp * cell + dir * cell, origin + dir * cell,
			]), col)


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
