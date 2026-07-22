class_name SeriesData
extends Resource
## A championship. Everything career-related reads this — one series now, N later.

@export var id: String = ""
@export var series_name: String = ""
## Promotion/relegation hook — unused in Milestone 1.
@export var tier: int = 1
@export var team_ids: PackedStringArray = []
@export var calendar_track_ids: PackedStringArray = []
@export var race_laps: int = 25
@export var allowed_compound_ids: PackedStringArray = []
@export var points_table: PackedInt32Array = []
