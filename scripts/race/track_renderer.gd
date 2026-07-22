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
## Curve offset (px) where each segment starts; [n] = full length (wrap).
var _seg_offsets: PackedFloat32Array = []


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	if path == null or path.curve == null:
		return
	_baked = path.curve.get_baked_points()
	_baked_len = path.curve.get_baked_length()
	_build_segment_offsets()
	queue_redraw()


## Anchor-aligned sim->curve mapping (falls back to proportional-by-length).
func _build_segment_offsets() -> void:
	_seg_offsets.clear()
	if track_data == null:
		return
	var n := track_data.segment_count()
	var idx := track_data.segment_anchor_indices
	_seg_offsets.resize(n + 1)
	if idx.size() == n and path.anchor_points.size() > 0:
		for i in n:
			var anchor := path.anchor_points[idx[i]]
			_seg_offsets[i] = path.curve.get_closest_offset(anchor)
		_seg_offsets[0] = 0.0
	else:
		var total := track_data.total_length_m()
		for i in n:
			_seg_offsets[i] = track_data.cum_length_m(i) / total * _baked_len
	_seg_offsets[n] = _baked_len


## Visual curve offset for a sim position (segment index + 0-1 progress).
func segment_offset(seg: int, progress: float) -> float:
	if _seg_offsets.is_empty():
		_refresh()
		if _seg_offsets.is_empty():
			return 0.0
	return lerpf(_seg_offsets[seg], _seg_offsets[seg + 1], clampf(progress, 0.0, 1.0))


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
		_draw_grid_slots()
	_draw_start_line()
	if Engine.is_editor_hint() and track_data:
		_draw_segment_tints()


## Red/white dashes along both edges of every corner + corner numbers.
func _draw_kerbs() -> void:
	if _label_font == null:
		_label_font = ThemeDB.fallback_font
	var corner_n := 0
	for i in track_data.segment_count():
		var seg := track_data.get_segment(i)
		if seg.type != TrackSegment.Type.CORNER:
			continue
		corner_n += 1
		var o0 := _seg_offsets[i]
		var o1 := _seg_offsets[i + 1]
		var dashes := maxi(int((o1 - o0) / KERB_DASH_PX), 2)
		for d in dashes:
			var pa := sample(lerpf(o0, o1, float(d) / dashes))
			var pb := sample(lerpf(o0, o1, (d + 0.82) / dashes))
			var dir := (pb - pa).normalized()
			var perp := Vector2(-dir.y, dir.x)
			var col := KERB_RED if d % 2 == 0 else KERB_WHITE
			var off := TRACK_WIDTH * 0.5 + 3.5
			draw_line(pa + perp * off, pb + perp * off, col, 4.5)
			draw_line(pa - perp * off, pb - perp * off, col, 4.5)
		# Corner number, tucked outside the apex.
		var mid := sample((o0 + o1) * 0.5)
		var mdir := direction_at((o0 + o1) * 0.5)
		var mperp := Vector2(-mdir.y, mdir.x)
		# Outward = away from the polygon centroid.
		var centroid := Vector2(960, 480)
		var outward: Vector2 = mperp if mperp.dot(mid - centroid) > 0.0 else -mperp
		draw_string(_label_font, mid + outward * (TRACK_WIDTH * 0.5 + 22.0) + Vector2(-8, 5),
				"T%d" % corner_n, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.53, 0.6))


## Staggered grid slot markers behind the start line (first 10 boxes only,
## so they stay on the straight).
func _draw_grid_slots() -> void:
	for i in 10:
		var off := fposmod(-26.0 - i * 14.0, _baked_len)
		var p := sample(off)
		var dir := direction_at(off)
		var perp := Vector2(-dir.y, dir.x)
		var lane := 7.0 if i % 2 == 0 else -7.0
		var base := p + perp * lane
		draw_line(base - perp * 4.5, base + perp * 4.5, Color(1, 1, 1, 0.30), 2.0)
		draw_line(base - perp * 4.5 + dir * 6.0, base - perp * 4.5, Color(1, 1, 1, 0.30), 2.0)
		draw_line(base + perp * 4.5 + dir * 6.0, base + perp * 4.5, Color(1, 1, 1, 0.30), 2.0)


## DRS zones as a thin stripe along the edge of the ribbon, off the racing line.
func _draw_zones() -> void:
	for i in track_data.segment_count():
		var seg := track_data.get_segment(i)
		if not seg.drs_zone:
			continue
		var pts := _points_between_offsets(_seg_offsets[i], _seg_offsets[i + 1])
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
	for i in track_data.segment_count():
		var seg := track_data.get_segment(i)
		var pts := _points_between_offsets(_seg_offsets[i], _seg_offsets[i + 1])
		if pts.size() < 2:
			continue
		var col := Color(0.3, 0.9, 0.3, 0.8)
		if seg.type == TrackSegment.Type.CORNER:
			col = [Color(0.95, 0.35, 0.2, 0.8), Color(0.95, 0.6, 0.2, 0.8), Color(0.95, 0.8, 0.3, 0.8)][seg.corner_class - 1]
		draw_polyline(pts, col, 3.0)
		draw_circle(pts[0], 5.0, Color.WHITE)


func _points_between_offsets(o0: float, o1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := maxi(int((o1 - o0) / 14.0), 2)
	for s in steps + 1:
		pts.append(sample(lerpf(o0, o1, float(s) / steps)))
	return pts
