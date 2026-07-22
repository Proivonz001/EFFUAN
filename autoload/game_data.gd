extends Node
## Autoload singleton. Loads and indexes all game content (.tres) at boot and holds
## the "current race setup". The only autoload in the project — keep it that way.

var compounds: Dictionary = {}   # id -> TyreCompound
var drivers: Dictionary = {}     # id -> DriverData
var teams: Dictionary = {}       # id -> TeamData
var tracks: Dictionary = {}      # id -> TrackData
var series: Dictionary = {}      # id -> SeriesData

var current_series_id: String = "effuan_one"
var current_track_id: String = ""
var player_team_id: String = "meteora"


func _ready() -> void:
	load_all()


func load_all() -> void:
	compounds = _load_dir("res://data/compounds")
	drivers = _load_dir("res://data/drivers")
	teams = _load_dir("res://data/teams")
	tracks = _load_dir("res://data/tracks")
	series = _load_dir("res://data/series")
	var s := get_current_series()
	if s and not s.calendar_track_ids.is_empty():
		current_track_id = s.calendar_track_ids[0]


func get_current_series() -> SeriesData:
	return series.get(current_series_id)


func get_current_track() -> TrackData:
	return tracks.get(current_track_id)


func get_compound(id: String) -> TyreCompound:
	return compounds.get(id)


## Race entries for a series: one {team, driver} dict per car, two per team.
func build_entries(s: SeriesData) -> Array:
	var entries: Array = []
	for team_id in s.team_ids:
		var team: TeamData = teams.get(team_id)
		if team == null:
			push_error("Unknown team id '%s' in series '%s'" % [team_id, s.id])
			continue
		for driver_id in team.driver_ids:
			var driver: DriverData = drivers.get(driver_id)
			if driver == null:
				push_error("Unknown driver id '%s' in team '%s'" % [driver_id, team_id])
				continue
			entries.append({"team": team, "driver": driver})
	return entries


func _load_dir(path: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Cannot open data directory: " + path)
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and (fname.ends_with(".tres") or fname.ends_with(".res")):
			var res := load(path + "/" + fname)
			if res and "id" in res and res.id != "":
				out[res.id] = res
			else:
				push_error("Resource missing 'id': " + path + "/" + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return out
