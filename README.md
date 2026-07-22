# EFFUAN

A modern, minimalist F1 management game built in **Godot 4** (GDScript).
Golden Lap's clean 2D pacing meets Motorsport Manager's technical depth:
ERS deployment, DRS zones, tyre thermal windows, dirty air, undercuts —
in races that last 5-8 real minutes.

![Godot 4.7](https://img.shields.io/badge/Godot-4.7-blue)

## Milestone 1 — "Watchable Race" (done)

- **Segment-based race engine** (Motorsport Manager "TimeCost" style): the lap is
  split into corner/straight segments; each car's traversal time is computed from
  driver skill, car stats (aero/power/chassis), tyre grip, fuel load, ERS mode,
  fuel mixture, dirty air and DRS. Deterministic 20 Hz fixed tick, fully
  headless-testable, races compressed with an 8× time scale (toggle 1×/4×/8×).
- **Tyre thermal model**: grip is a function of wear *and* temperature (thermal
  window per compound). Overheating degrades tyres exponentially; wear past 65%
  hits a grip cliff. Hot → wear → cliff → pit is the core strategy loop.
- **Overtaking**: per-zone pass chance from pace delta, driver skills, DRS and
  ERS Overtake, with a "train clamp" so blocked cars queue up realistically.
- **Broadcast-style 2D visuals**: vector track ribbon with DRS zones, cars with
  team-colored trails and shadows, live timing tower, pit wall panel
  (ERS / fuel mix / compound / BOX) for the player team's two cars.
- **Data-driven content**: teams, drivers, compounds, tracks and series are
  editable `.tres` text resources under `data/` — fictional roster included.
  The series schema already supports multiple championships (tiers) for the
  planned promotion/relegation career.

## Running

Open the project with Godot 4.x and press **F5** — it boots straight into a race.
Player team: Meteora F1 (change `player_team_id` in `autoload/game_data.gd`).

### Headless tests

```
godot --headless --path . -s res://tests/test_tyre_model.gd
godot --headless --path . -s res://tests/headless_race.gd
```

`headless_race.gd` is the balance dashboard: it simulates a full 25-lap race and
asserts race duration, pit counts, lap-time sanity, overtake volume, field
spread and determinism.

### Debug screenshot

```
godot --path . -- --screenshot=90
```

Runs the game, saves a screenshot after 90 s to `user://screenshot.png`, quits.

## Project layout

```
autoload/game_data.gd     content loader/index (the only autoload)
scripts/resources/        data schema (Resource classes)
scripts/sim/              pure simulation - no Node deps (engine, tyres, overtaking)
scripts/race/             scene glue (manager, track renderer, cars)
scripts/ui/               leaderboard, pit wall, results
data/                     editable .tres content (teams, drivers, tracks, series)
scenes/                   main, race, track scenes
tests/                    headless test suites
```

## Roadmap

- Weather + inters/wets crossover, safety car
- Qualifying session, race weekend flow
- Season/career shell: calendar, standings, multi-series promotion
- R&D (aero/power/chassis pillars, risk vs reliability)
- More tracks, driver market
