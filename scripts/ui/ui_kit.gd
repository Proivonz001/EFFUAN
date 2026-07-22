class_name UIKit
extends RefCounted
## Shared UI vocabulary: palette constants + widget factories.
## Every screen builds its controls through these so look and behaviour
## (including click sounds) stay consistent and tweakable in one place.

# ------------------------------------------------------------------ palette --
const BG_DEEP := Color(0.055, 0.06, 0.075)
const BG_PANEL := Color(0.10, 0.11, 0.135)
const BG_PANEL_RAISED := Color(0.13, 0.145, 0.175)
const EDGE := Color(0.22, 0.24, 0.29)
const TEXT := Color(0.88, 0.90, 0.94)
const TEXT_DIM := Color(0.58, 0.61, 0.68)
const TEXT_FAINT := Color(0.42, 0.45, 0.52)
const ACCENT := Color(0.95, 0.30, 0.24)        # EFFUAN red
const GOLD := Color(1.0, 0.84, 0.30)           # player highlight
const GOOD := Color(0.42, 0.92, 0.55)
const WARN := Color(1.0, 0.75, 0.35)
const BAD := Color(1.0, 0.45, 0.40)
const INFO := Color(0.45, 0.72, 1.0)
const SC_YELLOW := Color(1.0, 0.90, 0.20)
# ------------------------------------------------------------------------------


static func label(text: String, size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func section(text: String) -> Label:
	return label(text.to_upper(), 11, TEXT_FAINT)


static func button(text: String, min_size: Vector2 = Vector2(100, 44),
		font_size: int = 14, handler: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: Sfx.click())
	if handler.is_valid():
		b.pressed.connect(handler)
	return b


static func set_active(b: Button, active: bool) -> void:
	b.modulate = Color(0.62, 1.0, 0.70) if active else Color.WHITE


static func hspacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


static func vspacer(height: float = -1.0) -> Control:
	var s := Control.new()
	if height > 0.0:
		s.custom_minimum_size = Vector2(0, height)
	else:
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


static func team_bar(color: Color, height: float = 16.0) -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(5, height)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.color = color
	return r
