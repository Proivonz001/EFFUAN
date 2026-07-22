class_name TrackSegment
extends Resource
## One logical piece of a lap. Corner classes: 1 = slow (hairpin), 2 = medium, 3 = fast sweeper.

enum Type { STRAIGHT, CORNER }

@export var type: Type = Type.STRAIGHT
@export var length_m: float = 200.0
@export_range(0, 3) var corner_class: int = 0
@export var drs_zone: bool = false
## 1.0 = normal, lower = easier passing zone (long straight into heavy braking).
@export var overtaking_difficulty: float = 1.0
