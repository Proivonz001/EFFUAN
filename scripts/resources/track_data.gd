class_name TrackData
extends Resource

@export var id: String = ""
@export var track_name: String = ""
## Untyped Array so hand-edited .tres files load leniently; elements are TrackSegment.
@export var segments: Array = []
@export var pit_lane_time_loss: float = 21.0
## Ideal setup balance for this track: -1 = low drag (power track), +1 = high downforce.
@export_range(-1.0, 1.0) var df_bias: float = 0.0
## Reference lap for a perfect car — tuning anchor, not enforced.
@export var base_lap_time: float = 80.0
@export var ambient_temp_c: float = 24.0
@export var scene_path: String = ""
## Anchor index (in TrackPath.anchor_points) where each segment starts.
## Aligns the sim segments with the drawn curve — cars, kerbs and DRS stripes
## all land exactly where the corner is drawn. Empty = legacy proportional map.
@export var segment_anchor_indices: PackedInt32Array = []

var _total_length: float = -1.0
var _cum_lengths: PackedFloat32Array = []


func total_length_m() -> float:
	if _total_length < 0.0:
		_build_cache()
	return _total_length


## Cumulative length at the START of segment i (index 0 -> 0.0).
func cum_length_m(i: int) -> float:
	if _total_length < 0.0:
		_build_cache()
	return _cum_lengths[i]


func segment_count() -> int:
	return segments.size()


func get_segment(i: int) -> TrackSegment:
	return segments[i] as TrackSegment


func _build_cache() -> void:
	_cum_lengths.resize(segments.size())
	var acc := 0.0
	for i in segments.size():
		_cum_lengths[i] = acc
		acc += (segments[i] as TrackSegment).length_m
	_total_length = acc
