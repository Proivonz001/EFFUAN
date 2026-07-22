class_name DriverData
extends Resource
## All skills on a 0-100 scale.

@export var id: String = ""
@export var driver_name: String = ""
## 3-letter timing-screen code (e.g. "VOS").
@export var code: String = ""
@export var skill_pace: float = 70.0
@export var skill_consistency: float = 70.0
@export var skill_overtaking: float = 70.0
@export var skill_defending: float = 70.0
@export var skill_tyre_mgmt: float = 70.0
