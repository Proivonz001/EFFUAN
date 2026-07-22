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

## Handle length as a fraction of the distance to each neighbour.
@export_range(0.0, 0.6) var smoothness: float = 0.36:
	set(value):
		smoothness = value
		_rebuild()


func _ready() -> void:
	_rebuild()


## Catmull-Rom direction with PER-SIDE clamped handle lengths: each handle is
## proportional to the distance of ITS neighbour, so a long straight feeding a
## tight corner no longer produces oversized tangents (the old visible kinks).
func _rebuild() -> void:
	var n := anchor_points.size()
	if n < 3:
		return
	var c := Curve2D.new()
	c.bake_interval = 4.0
	for i in n + 1:
		var idx := i % n
		var a := anchor_points[idx]
		var prev := anchor_points[(idx - 1 + n) % n]
		var next := anchor_points[(idx + 1) % n]
		var dir := (next - prev).normalized()
		var t_in := dir * (a.distance_to(prev) * smoothness)
		var t_out := dir * (a.distance_to(next) * smoothness)
		c.add_point(a, -t_in, t_out)
	curve = c
