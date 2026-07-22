# Track authoring standards ("i paletti")

Every circuit must respect these rules before it ships. They exist so that the
sim mapping, the renderer and the race furniture (grid, pit lane, camera) all
work without per-track hacks.

## Canvas & framing
- The FULL camera auto-fits the bounding box, so coordinates are free — but
  keep the layout aspect near 16:9 and DRAW BIG (current tracks use roughly
  x [230, 2230], y [110, 1100]; cars are fixed-size pixels, so a larger
  drawing = a longer-feeling circuit).
- No two track sections closer than **110 px** to each other (edges + kerbs +
  scenery need clearance; trees are auto-rejected within 60 px).

## Anchors & geometry
- The curve builder (`TrackPath`) uses per-side clamped tangents: handle length
  is proportional to the distance of *that* neighbour. This kills kinks, but
  still: **place 2-4 anchors per corner** (entry, apex/apexes, exit) and **1-2
  mid-straight**; never let a straight anchor sit closer than ~40 px to a
  corner anchor.
- Corner radii: hairpins ≥ 45 px between entry and exit anchors; fast sweepers
  wide and shallow. If the drawn ribbon pinches, spread the anchors.
- `smoothness` stays at the default 0.36 unless a layout truly needs it.

## Segments & alignment
- Every segment start MUST be pinned in `TrackData.segment_anchor_indices`
  (same count as `segments`, index 0 = 0). This aligns sim positions, kerbs,
  DRS stripes and corner numbers with the drawn shape. **No proportional
  fallback in shipped tracks.**
- Nominal lengths per type: class-1 corner 80-120 m, class-2 130-180 m,
  class-3 200-350 m, straights 150-1100 m. Target base lap 68-82 s
  (sum of length/speed at 26 / 42 / 62 / 78 m/s).

## Start/finish & grid
- The s/f line (anchor 0) sits on the longest straight with at least
  **310 px of straight BEHIND the line** (20 staggered grid boxes reach
  ~-285 px) and **130 px ahead** (pit exit merge). RaceManager converts each
  painted box to sim meters at setup, so the formation and the sim always
  agree — never rely on visual-only placement.
- The pit lane is auto-drawn on the **infield side** of the s/f straight from
  offset -340 to +70: keep that side clear of other track sections.

## Width
- Base ribbon 34 px (two cars race side by side; wide zones fit three).
  Use `TrackSegment.width_scale` 1.1-1.25 on the grid straight and on
  heavy-braking hairpins (real circuits widen there); never below 0.9 or
  above 1.3. The renderer blurs transitions automatically.

## Race furniture
- 1-2 DRS zones on the longest straights, `overtaking_difficulty` 0.5-0.7
  there; hairpin exits 0.85-0.95; fast sweepers 1.5-1.7.
- Set `df_bias` for the track character (-1 power .. +1 downforce),
  `ambient_temp_c`, `pit_lane_time_loss` (19-23 s) and `base_lap_time`.

## Workflow
1. Design the segment table (lengths, classes, DRS, widths) → `.tres`.
2. Place anchors matching the segment sequence; note the anchor index of each
   segment start → `segment_anchor_indices`.
3. Generate the scene via a pack/save script (see git history: tmp_gen_tracks).
4. Verify with the in-editor tint overlay (`@tool` renderer: green straights /
   orange corners must sit exactly on the drawn shape) and one
   `--test-race --screenshot` run: check kerbs, grid boxes, pit lane, camera fit.
