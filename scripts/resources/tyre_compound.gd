class_name TyreCompound
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var display_color: Color = Color.WHITE
## Peak grip multiplier with fresh tyres in the thermal window. Soft ~1.0, hard ~0.97.
@export var base_grip: float = 1.0
@export var optimal_temp_c: float = 100.0
## Half-width of the thermal window (Gaussian falloff).
@export var temp_window_c: float = 12.0
## Fraction of tyre life consumed per clean lap at optimal temperature (0.04 = 4%).
@export var base_wear_per_lap: float = 0.025
