# EFFUAN

A modern, minimalist F1 management game built in **Godot 4** (GDScript).
Golden Lap's clean 2D pacing meets Motorsport Manager's technical depth:
ERS deployment, DRS zones, tyre thermal windows, dirty air, undercuts —
in races that last 5-8 real minutes.

![Godot 4.7](https://img.shields.io/badge/Godot-4.7-blue)

## Milestone 3 — Quality Pass (done)

- **Visual identity**: global custom Theme (regenerate with
  `tests/gen_theme.gd`), [Titillium Web](https://fonts.google.com/specimen/Titillium+Web)
  typography (SIL OFL, bundled in `assets/fonts/`), shared `UIKit` palette
  and widget factories used by every screen.
- **Race view**: red/white kerbs on every corner, checkered start line, DRS
  zone labels, radial-vignette backdrop, rain particles + asphalt that
  darkens with wetness, F1-silhouette cars with DRS-open flap glow and ERS
  deploy indicator, start-light sequence, position-change markers in the
  timing tower.
- **Timing precision**: sub-tick interpolation — lap and finish times are
  millisecond-accurate instead of quantized to the sim tick.
- **Audio**: fully procedural (zero asset files) — UI clicks, radio beeps,
  SC alert, start lights, ambient engine bed pitched by time scale.

## Milestone 2 — Vertical Slice (done)

The full concept loop is playable: **menu → season hub → setup + qualifying →
race → results → hub … → season end with promotion/relegation → next season.**

- **Career**: start at mid-grid **Aquila Corse in Series Two** and fight for
  promotion. Two 10-team series, 6-round season over 4 circuits, points,
  standings, bottom-2/top-2 swap at season end. JSON autosave (`user://career.json`).
- **Dynamic weather**: per-race forecast scenarios (dry / showers / wet-drying /
  building rain), track wetness that integrates rain vs drying, slick→inter→wet
  crossover points, AI pit reactions, live weather widget with forecast.
- **R&D**: pick a pillar (aero/power/chassis) and a risk level each round —
  aggressive programs gain more but erode **reliability**, which feeds a real
  mechanical-DNF probability in races. AI teams develop too.
- **Setup & confidence**: one pre-race downforce slider vs. each track's ideal
  balance; instant one-lap qualifying builds the grid; drivers carry a
  confidence rating that reacts to results and setup quality.
- **4 circuits** with distinct characters: Levante (balanced), Anello di
  Ponente (power), Passo Serrano (high downforce), Baia Azzurra (street).

### Vertical-slice tests

```
godot --headless --path . -s res://tests/test_wet_race.gd     # forced storm: field switches to rain tyres
godot --headless --path . -- --test-season                    # automated 6-round career incl. promotion
```

Debug flags (after `--`): `--test-hub`, `--test-setup`, `--test-race`,
`--screenshot=N`.

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
