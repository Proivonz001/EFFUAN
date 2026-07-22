@tool
class_name TrackPath
extends Path2D
## Builds a smooth closed Curve2D from a hand-editable list of anchor points
## (Catmull-Rom style tangents). Edit `anchor_points` in the inspector and the
## curve regenerates — no manual bezier handle fiddling.

@export var anchor_points: PackedVector2Array = []:
	set(value):
		anchor_points = value
		_rebuild()

## Tangent length as a fraction of the neighbour-to-neighbour distance.
@export_range(0.0, 0.5) var smoothness: float = 0.22:
	set(value):
		smoothness = value
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	var n := anchor_points.size()
	if n < 3:
		return
	var c := Curve2D.new()
	c.bake_interval = 8.0
	for i in n:
		var prev := anchor_points[(i - 1 + n) % n]
		var next := anchor_points[(i + 1) % n]
		var tangent := (next - prev) * smoothness
		c.add_point(anchor_points[i], -tangent, tangent)
	# Close the loop by repeating the first point (same handles).
	var prev0 := anchor_points[n - 1]
	var next0 := anchor_points[1]
	var tan0 := (next0 - prev0) * smoothness
	c.add_point(anchor_points[0], -tan0, tan0)
	curve = c
