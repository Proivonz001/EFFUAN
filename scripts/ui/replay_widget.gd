class_name ReplayWidget
extends PanelContainer
## Mini replay window: re-runs the last ~5 seconds of a notable overtake at
## half speed, drawn from recorded car positions over the local track geometry.

const PLAYBACK_SPEED := 0.5
const FRAME_DT := 0.1

var manager: RaceManager

var _data := {}
var _t := 0.0
var _duration := 0.0
var _canvas: Control
var _head: Label


func _ready() -> void:
	manager = get_node("../..")
	manager.replay_ready.connect(_on_replay)
	visible = false

	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -404.0
	offset_right = -24.0
	offset_top = 150.0
	offset_bottom = 420.0

	var vbox := VBoxContainer.new()
	add_child(vbox)
	_head = Label.new()
	_head.add_theme_font_size_override("font_size", 13)
	_head.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
	vbox.add_child(_head)
	_canvas = Control.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.draw.connect(_draw_replay)
	_canvas.clip_contents = true
	vbox.add_child(_canvas)


func _on_replay(data: Dictionary) -> void:
	_data = data
	_t = 0.0
	_duration = data.frames.size() * FRAME_DT / PLAYBACK_SPEED
	_head.text = "REPLAY   %s  >  %s" % [data.code_a, data.code_b]
	visible = true
	modulate = Color.WHITE


func _process(delta: float) -> void:
	if not visible or _data.is_empty():
		return
	_t += delta
	if _t > _duration + 1.0:
		visible = false
		_data = {}
		return
	if _t > _duration:
		modulate = Color(1, 1, 1, 1.0 - (_t - _duration))
	_canvas.queue_redraw()


func _draw_replay() -> void:
	if _data.is_empty():
		return
	var bbox: Rect2 = _data.bbox
	var cs: Vector2 = _canvas.size
	var scale: float = minf(cs.x / bbox.size.x, cs.y / bbox.size.y) * 0.92
	var origin: Vector2 = cs * 0.5 - bbox.get_center() * scale

	# Local track geometry.
	for chunk in _data.chunks:
		var pts := PackedVector2Array()
		for p in chunk:
			pts.append(origin + p * scale)
		if pts.size() > 1:
			_canvas.draw_polyline(pts, Color(0.3, 0.32, 0.38, 0.9), 34.0 * scale)

	# Playback position (interpolated between recorded frames).
	var frames: Array = _data.frames
	var ft: float = clampf(_t * PLAYBACK_SPEED / FRAME_DT, 0.0, frames.size() - 1.001)
	var i := int(ft)
	var frac := ft - i
	var fa: Dictionary = frames[i]
	var fb: Dictionary = frames[mini(i + 1, frames.size() - 1)]

	# Trails up to the playhead.
	var trail_a := PackedVector2Array()
	var trail_b := PackedVector2Array()
	for j in range(maxi(0, i - 14), i + 1):
		trail_a.append(origin + frames[j].a * scale)
		trail_b.append(origin + frames[j].b * scale)
	if trail_a.size() > 1:
		_canvas.draw_polyline(trail_a, Color(_data.col_a, 0.4), 2.0)
	if trail_b.size() > 1:
		_canvas.draw_polyline(trail_b, Color(_data.col_b, 0.4), 2.0)

	var pa: Vector2 = origin + fa.a.lerp(fb.a, frac) * scale
	var pb: Vector2 = origin + fa.b.lerp(fb.b, frac) * scale
	_canvas.draw_circle(pa, 5.0, _data.col_a)
	_canvas.draw_circle(pb, 5.0, _data.col_b)
	var font := ThemeDB.fallback_font
	_canvas.draw_string(font, pa + Vector2(7, -6), _data.code_a,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.9))
	_canvas.draw_string(font, pb + Vector2(7, -6), _data.code_b,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.9))
