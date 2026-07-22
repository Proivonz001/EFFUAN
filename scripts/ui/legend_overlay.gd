class_name LegendOverlay
extends CenterContainer
## In-race help sheet, toggled with H — explains every indicator on screen.

const ENTRIES := [
	["GOLD TAG", "your two cars (others show team-coloured codes)"],
	["GREEN REAR WING", "DRS open: within 1s in a DRS zone"],
	["PINK GLOW BEHIND A CAR", "ERS battery deploying (DEPLOY / OVERTAKE)"],
	["OVERTAKE ✓", "boost armed: you crossed the line within 1s of the car ahead"],
	["TYRE RING (card)", "remaining tyre life, amber/red near the cliff"],
	["RING CORE COLOUR", "tyre temperature: blue cold · green in window · red hot"],
	["GREEN / PURPLE DOT (tower)", "personal / session best sector"],
	["PURPLE DRIVER CODE", "current fastest-lap holder"],
	["+N / -N (tower)", "positions gained / lost just now"],
	["WEAR % COLOUR", "green fresh · amber going off · red at the cliff"],
	["BLUE BARS (radar)", "rain intensity ahead on the timeline"],
	["SPACE / 1 2 3 / C / H", "pause · time scale · camera · this help"],
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var panel := PanelContainer.new()
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UIKit.label("RACE SCREEN LEGEND", 20))
	v.add_child(HSeparator.new())
	for entry in ENTRIES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var key := UIKit.label(entry[0], 13, UIKit.GOLD)
		key.custom_minimum_size = Vector2(240, 0)
		row.add_child(key)
		row.add_child(UIKit.label(entry[1], 13, UIKit.TEXT_DIM))
		v.add_child(row)
	v.add_child(HSeparator.new())
	v.add_child(UIKit.label("press  H  to close", 12, UIKit.TEXT_FAINT))


func toggle() -> void:
	visible = not visible
