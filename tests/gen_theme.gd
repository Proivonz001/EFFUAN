extends SceneTree
## One-off generator: builds the global UI Theme and saves it as .tres.
## Rerun after changing UIKit palette values.

const UIKitScript := preload("res://scripts/ui/ui_kit.gd")


func _initialize() -> void:
	var theme := Theme.new()

	var font_regular: FontFile = load("res://assets/fonts/TitilliumWeb-Regular.ttf")
	var font_semibold: FontFile = load("res://assets/fonts/TitilliumWeb-SemiBold.ttf")
	var font_bold: FontFile = load("res://assets/fonts/TitilliumWeb-Bold.ttf")
	theme.default_font = font_regular
	theme.default_font_size = 15

	# ---- Panels ----
	var panel := StyleBoxFlat.new()
	panel.bg_color = UIKitScript.BG_PANEL
	panel.set_corner_radius_all(8)
	panel.set_border_width_all(1)
	panel.border_color = UIKitScript.EDGE
	panel.set_content_margin_all(14.0)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel.duplicate())

	# ---- Buttons ----
	var btn := StyleBoxFlat.new()
	btn.bg_color = UIKitScript.BG_PANEL_RAISED
	btn.set_corner_radius_all(6)
	btn.set_border_width_all(1)
	btn.border_color = UIKitScript.EDGE
	btn.content_margin_left = 12.0
	btn.content_margin_right = 12.0
	btn.content_margin_top = 6.0
	btn.content_margin_bottom = 6.0

	var btn_hover: StyleBoxFlat = btn.duplicate()
	btn_hover.bg_color = Color(0.175, 0.195, 0.235)
	btn_hover.border_color = Color(0.35, 0.38, 0.45)

	var btn_pressed: StyleBoxFlat = btn.duplicate()
	btn_pressed.bg_color = Color(0.08, 0.09, 0.11)
	btn_pressed.border_color = UIKitScript.ACCENT

	var btn_disabled: StyleBoxFlat = btn.duplicate()
	btn_disabled.bg_color = Color(0.09, 0.095, 0.115)
	btn_disabled.border_color = Color(0.15, 0.16, 0.19)

	theme.set_stylebox("normal", "Button", btn)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("disabled", "Button", btn_disabled)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_font("font", "Button", font_semibold)
	theme.set_color("font_color", "Button", UIKitScript.TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", UIKitScript.TEXT)
	theme.set_color("font_disabled_color", "Button", Color(0.4, 0.42, 0.48))

	# ---- Labels ----
	theme.set_color("font_color", "Label", UIKitScript.TEXT)

	# ---- ProgressBar ----
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.07, 0.075, 0.09)
	pb_bg.set_corner_radius_all(3)
	pb_bg.set_border_width_all(1)
	pb_bg.border_color = UIKitScript.EDGE
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = UIKitScript.INFO
	pb_fill.set_corner_radius_all(3)
	theme.set_stylebox("background", "ProgressBar", pb_bg)
	theme.set_stylebox("fill", "ProgressBar", pb_fill)

	# ---- HSlider ----
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.07, 0.075, 0.09)
	slider_bg.set_corner_radius_all(3)
	slider_bg.content_margin_top = 3.0
	slider_bg.content_margin_bottom = 3.0
	var grabber_area := StyleBoxFlat.new()
	grabber_area.bg_color = UIKitScript.ACCENT
	grabber_area.set_corner_radius_all(3)
	theme.set_stylebox("slider", "HSlider", slider_bg)
	theme.set_stylebox("grabber_area", "HSlider", grabber_area)
	theme.set_stylebox("grabber_area_highlight", "HSlider", grabber_area.duplicate())

	# ---- Separators ----
	var sep := StyleBoxLine.new()
	sep.color = UIKitScript.EDGE
	theme.set_stylebox("separator", "HSeparator", sep)

	# ---- Tooltips / misc ----
	theme.set_font("bold_font", "RichTextLabel", font_bold)

	var err := ResourceSaver.save(theme, "res://theme/effuan_theme.tres")
	print("theme saved err=", err)
	quit(0 if err == OK else 1)
