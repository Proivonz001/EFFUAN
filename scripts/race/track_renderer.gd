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
const PIT_LANE_DEPTH := 36.0

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
## Smoothed visual width sampled every WIDTH_STEP px along the lap.
const WIDTH_STEP := 7.0
var _widths: PackedFloat32Array = []


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	if path == null or path.curve == null:
		return
	_baked = path.curve.get_baked_points()
	_baked_len = path.curve.get_baked_length()
	_build_segment_offsets()
	_build_widths()
	queue_redraw()


## Per-sample width from segment width_scale, smoothed so transitions flow.
func _build_widths() -> void:
	_widths.clear()
	var n := int(ceil(_baked_len / WIDTH_STEP))
	if n <= 0:
		return
	_widths.resize(n)
	var seg := 0
	for k in n:
		var off := k * WIDTH_STEP
		var w := TRACK_WIDTH
		if track_data and not _seg_offsets.is_empty():
			while seg < track_data.segment_count() - 1 and off >= _seg_offsets[seg + 1]:
				seg += 1
			w = TRACK_WIDTH * track_data.get_segment(seg).width_scale
		_widths[k] = w
	# Wrap-around box blur passes to melt the steps into ramps.
	for pass_i in 4:
		var out := _widths.duplicate()
		for k in n:
			out[k] = (_widths[(k - 2 + n) % n] + _widths[(k - 1 + n) % n] + _widths[k]
					+ _widths[(k + 1) % n] + _widths[(k + 2) % n]) / 5.0
		_widths = out


func width_at(off: float) -> float:
	if _widths.is_empty():
		return TRACK_WIDTH
	return _widths[int(fposmod(off, _baked_len) / WIDTH_STEP) % _widths.size()]


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

	if track_data:
		_draw_scenery()
	_draw_pit_lane()

	# Variable-width asphalt as a quad strip + crisp per-side edge lines.
	var asphalt := ASPHALT.lerp(ASPHALT_WET, wetness)
	var left_edge := PackedVector2Array()
	var right_edge := PackedVector2Array()
	var o := 0.0
	while o <= _baked_len + WIDTH_STEP:
		var off := minf(o, _baked_len)
		var p := sample(off)
		var dir := direction_at(off)
		var perp := Vector2(-dir.y, dir.x)
		var half := width_at(off) * 0.5
		left_edge.append(p - perp * half)
		right_edge.append(p + perp * half)
		o += WIDTH_STEP
	for i in range(left_edge.size() - 1):
		draw_colored_polygon(PackedVector2Array([
			left_edge[i], left_edge[i + 1], right_edge[i + 1], right_edge[i],
		]), asphalt)
	draw_polyline(left_edge, EDGE, 2.0, true)
	draw_polyline(right_edge, EDGE, 2.0, true)

	if track_data:
		_draw_kerbs()
		_draw_zones()
		_draw_grid_slots()
	_draw_start_line()


## The pit lane runs on the infield side of the s/f straight; the parked-car
## slots in Car2D (offset -70-i*26, perp -34) sit exactly on it.
func _draw_pit_lane() -> void:
	var lane_pts := PackedVector2Array()
	var step := 14.0
	var o := -520.0
	while o <= 70.0:
		var off := fposmod(o, _baked_len)
		var p := sample(off)
		var dir := direction_at(off)
		var perp := Vector2(-dir.y, dir.x)
		# Taper in/out at the ends so the lane merges into the track edge.
		var depth := PIT_LANE_DEPTH
		if o < -455.0:
			depth = remap(o, -520.0, -455.0, 4.0, PIT_LANE_DEPTH)
		elif o > 25.0:
			depth = remap(o, 25.0, 70.0, PIT_LANE_DEPTH, 4.0)
		lane_pts.append(p - perp * depth)
		o += step
	draw_polyline(lane_pts, Color(0.75, 0.76, 0.8, 0.5), 15.0)
	draw_polyline(lane_pts, Color(0.12, 0.13, 0.155), 12.0)

	# Pit building block behind the boxes + label.
	var mid_off := fposmod(-230.0, _baked_len)
	var mp := sample(mid_off)
	var mdir := direction_at(mid_off)
	var mperp := Vector2(-mdir.y, mdir.x)
	var b0 := mp - mperp * 50.0 - mdir * 95.0
	draw_colored_polygon(PackedVector2Array([
		b0, b0 + mdir * 190.0, b0 + mdir * 190.0 - mperp * 20.0, b0 - mperp * 20.0,
	]), Color(0.16, 0.175, 0.21))
	if _label_font == null:
		_label_font = ThemeDB.fallback_font
	draw_string(_label_font, mp - mperp * 56.0 + mdir * -14.0, "PIT",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.63, 0.7))


## Grandstands along the two longest straights + seeded trees around the map.
func _draw_scenery() -> void:
	# Grandstands: outside edge of the main straight and the longest other straight.
	var straights: Array = []
	for i in track_data.segment_count():
		if track_data.get_segment(i).type == TrackSegment.Type.STRAIGHT:
			straights.append(i)
	straights.sort_custom(func(a, b): return track_data.get_segment(a).length_m > track_data.get_segment(b).length_m)
	for s_idx in mini(2, straights.size()):
		var i: int = straights[s_idx]
		var o0: float = _seg_offsets[i] + 60.0
		var o1: float = _seg_offsets[i + 1] - 60.0
		var o := o0
		while o < o1:
			var p := sample(o)
			var dir := direction_at(o)
			var perp := Vector2(-dir.y, dir.x)
			# Stand on the outfield side (opposite the pit lane / infield).
			var base := p + perp * (TRACK_WIDTH * 0.5 + 16.0)
			for row in 3:
				var r0 := base + perp * (row * 7.0)
				var col := Color(0.14, 0.155, 0.19) if row % 2 == 0 else Color(0.17, 0.185, 0.225)
				draw_colored_polygon(PackedVector2Array([
					r0, r0 + dir * 62.0, r0 + dir * 62.0 + perp * 6.0, r0 + perp * 6.0,
				]), col)
			o += 78.0

	# Trees: deterministic per track, rejected if they'd overlap any track piece.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(track_data.id)
	var coarse := PackedVector2Array()
	for j in range(0, _baked.size(), 6):
		coarse.append(_baked[j])
	for attempt in 46:
		var off := rng.randf() * _baked_len
		var p := sample(off)
		var dir := direction_at(off)
		var perp := Vector2(-dir.y, dir.x)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var pos := p + perp * side * rng.randf_range(75.0, 170.0)
		var clear := true
		for cp in coarse:
			if cp.distance_squared_to(pos) < 3600.0:
				clear = false
				break
		if not clear:
			continue
		var r := rng.randf_range(6.0, 11.0)
		draw_circle(pos, r, Color(0.10, 0.16, 0.11))
		draw_circle(pos, r * 0.62, Color(0.13, 0.21, 0.14))
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
			var off := width_at(lerpf(o0, o1, float(d) / dashes)) * 0.5 + 3.5
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
## One painted box per grid position, staggered in two columns (P1 ahead on
## the right, P2 left, ...). Car2D parks each car on its own box pre-start.
## F1-realistic spacing: row pitch ~1.6 car lengths, columns staggered.
static func grid_slot_transform(grid_pos: int) -> Dictionary:
	var i := grid_pos - 1
	var row := i >> 1
	return {
		"offset": -46.0 - row * 42.0 - (16.0 if i % 2 == 1 else 0.0),
		"lane": 10.5 if i % 2 == 0 else -10.5,
	}


func _draw_grid_slots() -> void:
	for grid_pos in range(1, 21):
		var slot := grid_slot_transform(grid_pos)
		var off: float = fposmod(slot.offset, _baked_len)
		var p := sample(off)
		var dir := direction_at(off)
		var perp := Vector2(-dir.y, dir.x)
		var base: Vector2 = p + perp * slot.lane
		var col := Color(1, 1, 1, 0.32)
		draw_line(base - perp * 6.0 + dir * 9.0, base + perp * 6.0 + dir * 9.0, col, 2.0)
		draw_line(base - perp * 6.0 + dir * 9.0, base - perp * 6.0 - dir * 7.0, col, 2.0)
		draw_line(base + perp * 6.0 + dir * 9.0, base + perp * 6.0 - dir * 7.0, col, 2.0)


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
	var half := width_at(0.0) * 0.5
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
