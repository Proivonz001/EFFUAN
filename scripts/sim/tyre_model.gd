class_name TyreModel
extends RefCounted
## Pure static tyre math — zero Node dependencies, fully headless-testable.
## The hot->wear->cliff->pit coupling loop IS the strategy game.

# ------------------------------------------------------------------ tuning ---
const THERMAL_FLOOR := 0.90          # grip multiplier far outside the window
const THERMAL_PEAK_GAIN := 0.10      # extra grip at the exact optimal temp
const WEAR_LINEAR_SLOPE := 0.06      # gentle grip loss per 100% wear before the cliff
const WEAR_CLIFF_START := 0.65       # wear fraction where the cliff begins
const WEAR_CLIFF_STEEPNESS := 1.8    # quadratic cliff coefficient
const GRIP_FLOOR := 0.70             # absolute minimum wear factor

const OVERHEAT_MARGIN_C := 8.0       # degrees above optimal before wear explodes
const OVERHEAT_EXP_RATE := 0.06      # exponential wear rate per overheat degree
const TYRE_MGMT_WEAR_SAVING := 0.3   # max wear reduction from a 100-skill driver
const CHASSIS_WEAR_SAVING := 0.12    # max wear reduction from a 100-stat chassis

const HEAT_CORNER_C := 2.1           # heat added per corner segment at push 1.0
const HEAT_STRAIGHT_C := 0.35        # heat added per straight segment
const COOLING_COEFF := 0.017         # Newtonian cooling per segment toward ambient

# Wet weather. Crossover points emerge from the curves below:
# slick->inter around wetness 0.25, inter->wet around 0.65.
const WET_TREAD_WEAR_DRY_MULT := 2.5 # extra wear for inter/wet on a dry track
const RAIN_HEAT_LOSS := 0.5          # heat generation reduction at full wetness
const RAIN_COOLING_GAIN := 1.0       # extra cooling at full wetness
# ------------------------------------------------------------------------------


## Grip multiplier: compound base x thermal window x wear state x track wetness.
static func grip(compound: TyreCompound, wear: float, temp_c: float, wetness: float = 0.0) -> float:
	var dt := (temp_c - compound.optimal_temp_c) / compound.temp_window_c
	var thermal := THERMAL_FLOOR + THERMAL_PEAK_GAIN * exp(-dt * dt)
	var wear_factor := 1.0 - WEAR_LINEAR_SLOPE * wear
	if wear > WEAR_CLIFF_START:
		wear_factor -= WEAR_CLIFF_STEEPNESS * pow(wear - WEAR_CLIFF_START, 2.0)
	return compound.base_grip * thermal * maxf(wear_factor, GRIP_FLOOR) * wet_factor(compound, wetness)


## How well a compound copes with a given track wetness (multiplier <= 1).
static func wet_factor(compound: TyreCompound, wetness: float) -> float:
	match compound.id:
		"inter":
			return 0.96 - 0.45 * absf(wetness - 0.4)
		"wet":
			return 0.92 - 0.35 * absf(wetness - 0.85)
		_:
			# Slicks: fine on damp track, hopeless in real rain.
			return maxf(1.0 - 0.5 * wetness - 0.4 * maxf(0.0, wetness - 0.5), 0.25)


static func is_rain_tyre(compound: TyreCompound) -> bool:
	return compound.id == "inter" or compound.id == "wet"


## Wear added by traversing a segment. lap_fraction = segment share of a full lap.
static func wear_delta(compound: TyreCompound, temp_c: float, lap_fraction: float,
		tyre_mgmt_skill: float, chassis_stat: float, dirty_air_factor: float,
		wetness: float = 0.0) -> float:
	var rate := compound.base_wear_per_lap * lap_fraction
	var overheat := maxf(0.0, temp_c - (compound.optimal_temp_c + OVERHEAT_MARGIN_C))
	rate *= exp(OVERHEAT_EXP_RATE * overheat)
	rate *= 1.0 - TYRE_MGMT_WEAR_SAVING * (tyre_mgmt_skill / 100.0)
	rate *= 1.0 - CHASSIS_WEAR_SAVING * (chassis_stat / 100.0)
	rate *= dirty_air_factor
	if is_rain_tyre(compound) and wetness < 0.2:
		# Treaded tyres tear themselves apart on a dry surface.
		rate *= 1.0 + WET_TREAD_WEAR_DRY_MULT * (0.2 - wetness) / 0.2
	return rate


## Temperature change from traversing one segment.
## push_level: 1.0 = neutral running; pushing (rich mix, ERS deploy, dirty air) raises it.
static func temp_delta(is_corner: bool, temp_c: float, ambient_c: float, push_level: float,
		wetness: float = 0.0) -> float:
	var heat := (HEAT_CORNER_C if is_corner else HEAT_STRAIGHT_C) * push_level
	heat *= 1.0 - RAIN_HEAT_LOSS * wetness
	var cooling := COOLING_COEFF * (1.0 + RAIN_COOLING_GAIN * wetness) * (temp_c - ambient_c)
	return heat - cooling
