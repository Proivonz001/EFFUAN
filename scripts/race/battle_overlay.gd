class_name BattleOverlay
extends Node2D
## Draws a pulsing link between every pair of cars fighting within DRS range,
## so the hot spots of the race jump out on the map.

var manager: RaceManager


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if manager == null or manager.engine == null:
		return
	var order: Array = manager.engine.order
	var pulse := 0.35 + 0.2 * sin(Time.get_ticks_msec() * 0.006)
	for i in range(1, order.size()):
		var lead: CarData = order[i - 1]
		var chase: CarData = order[i]
		if lead.finished or chase.finished or lead.dnf or chase.dnf \
				or lead.in_pit or chase.in_pit or chase.gap_ahead_s > 1.0:
			continue
		var a: Vector2 = manager.car_node(lead.index).position
		var b: Vector2 = manager.car_node(chase.index).position
		if a.distance_squared_to(b) > 90000.0:   # visual glitch guard (lap wrap)
			continue
		var col := Color(1.0, 0.62, 0.2, pulse)
		if lead.is_player or chase.is_player:
			col = Color(1.0, 0.85, 0.3, pulse + 0.15)
		draw_line(a, b, col, 2.5)
		draw_arc(a.lerp(b, 0.5), 15.0, 0, TAU, 20, Color(col, col.a * 0.6), 1.5)
