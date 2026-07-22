class_name TeamData
extends Resource
## Car stats on a 0-100 scale. Drivers are linked by id and resolved by GameData.

@export var id: String = ""
@export var team_name: String = ""
@export var primary_color: Color = Color.WHITE
## Corner speed.
@export var stat_aero: float = 70.0
## Straight-line speed and ERS harvest rate.
@export var stat_power: float = 70.0
## Mild gains everywhere + tyre gentleness.
@export var stat_chassis: float = 70.0
@export var driver_ids: PackedStringArray = []
