class_name CarData
extends Resource
## Runtime race state for one car. Instantiated fresh at race start, never saved to disk.
## Only RaceEngine mutates this; UI and visuals read it.

enum ErsMode { HARVEST, NEUTRAL, DEPLOY, OVERTAKE }
enum FuelMix { LEAN, STANDARD, RICH }

# --- identity (set once at setup) ---
var index: int = -1
var driver: DriverData
var team: TeamData
var is_player: bool = false
var setup_bias: float = 0.0           # -1 low drag .. +1 high downforce
var confidence: float = 50.0          # 0-100, from career state
var reliability: float = 90.0         # 0-100, from R&D risk history

# --- live physical state ---
var fuel_kg: float = 0.0
var ers_charge: float = 50.0          # 0-100
var tyre_wear: float = 0.0            # 0.0-1.0
var tyre_temp_c: float = 70.0
var compound: TyreCompound

# --- pit wall commands ---
var ers_mode: ErsMode = ErsMode.NEUTRAL
## Locked for the whole race — chosen pre-race with the starting tyres.
var fuel_mix: FuelMix = FuelMix.STANDARD
var pit_requested: bool = false
var pit_target_compound: TyreCompound
## OVERTAKE boost token: earned by being within 1s at the detection point
## (the s/f line) on the previous lap; consumed on activation.
var overtake_available: bool = false

# --- sim position ---
var lap: int = 0                      # display lap, 1-based once the line is crossed
var laps_crossed: int = -1            # times over the s/f line; -1 = still behind it on the grid
var max_lap_seen: int = -1            # guard against double lap-events after battle clamps
var segment_index: int = 0
var segment_progress: float = 0.0     # 0-1 within current segment
var segment_time: float = 1.0         # traversal time of the current segment (sim s)
var current_speed: float = 50.0       # m/s through the current segment
var total_race_time: float = 0.0      # cumulative sim seconds
var race_distance_m: float = 0.0      # canonical ordering key, updated by the engine

# --- pit state ---
var in_pit: bool = false
var pit_time_remaining: float = 0.0
var pit_count: int = 0

# --- timing ---
var grid_pos: int = 0
var current_lap_start_time: float = 0.0
var last_lap_time: float = 0.0
var best_lap_time: float = 0.0
var sector_start_time: float = 0.0
var personal_best_sectors: Array = [0.0, 0.0, 0.0]
var last_sector_status: int = 0       # 0 none, 1 personal best (green), 2 session best (purple)
var finished: bool = false
var finish_time: float = 0.0
var dnf: bool = false                 # mechanical retirement

# --- battle bookkeeping (engine internal) ---
var gap_ahead_s: float = 99.0         # live gap to the car directly ahead on track
var attack_cooldown: int = 0          # segments until the next overtake attempt is allowed
var in_battle: bool = false           # true while actively attacking/defending (visual lane offset)
var drs_open: bool = false            # DRS active in the current segment (visual indicator)

# --- duel: the wheel-to-wheel phase of an overtake ---
var duel_with: int = -1               # partner car index, -1 = not dueling
var duel_role: int = 0                # 0 = attacker, 1 = defender
var duel_success: bool = false        # pre-rolled outcome, revealed at the braking zone
var duel_t: float = 0.0               # sim seconds spent side by side
var duel_lane: float = 0.0            # visual lane sign while dueling (+1 / -1)


func display_name() -> String:
	return driver.driver_name if driver else "?"


func short_code() -> String:
	return driver.code if driver else "???"
