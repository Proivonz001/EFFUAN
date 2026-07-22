extends Node
## Procedural sound effects — everything synthesized at boot, zero asset files.
## Public API: click(), radio(), sc_alert(), light_on(), lights_out(),
## start_ambient(), stop_ambient(), set_ambient_pitch().

const MIX_RATE := 22050

var _streams := {}
var _pool: Array = []
var _pool_index := 0
var _ambient_player: AudioStreamPlayer


func _ready() -> void:
	_streams["click"] = _tone([[900.0, 0.03]], 0.5, 0.008)
	_streams["radio"] = _tone([[1150.0, 0.05], [1500.0, 0.06]], 0.35, 0.01)
	_streams["sc"] = _tone([[720.0, 0.16], [940.0, 0.16], [720.0, 0.16], [940.0, 0.16]], 0.5, 0.02)
	_streams["light"] = _tone([[620.0, 0.09]], 0.45, 0.01)
	_streams["lights_out"] = _tone([[930.0, 0.35]], 0.55, 0.03)
	_streams["ambient"] = _make_ambient()

	for i in 6:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_pool.append(p)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.stream = _streams["ambient"]
	_ambient_player.volume_db = -21.0
	add_child(_ambient_player)


func click() -> void:
	_play("click", -14.0)


func radio() -> void:
	_play("radio", -12.0)


func sc_alert() -> void:
	_play("sc", -8.0)


func light_on() -> void:
	_play("light", -8.0)


func lights_out() -> void:
	_play("lights_out", -6.0)


func start_ambient() -> void:
	if not _ambient_player.playing:
		_ambient_player.play()


func stop_ambient() -> void:
	_ambient_player.stop()


func set_ambient_pitch(scale: float) -> void:
	_ambient_player.pitch_scale = clampf(scale, 0.7, 1.6)


func _play(key: String, volume_db: float) -> void:
	var p: AudioStreamPlayer = _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	p.stream = _streams[key]
	p.volume_db = volume_db
	p.play()


# ---------------------------------------------------------------- synthesis ---

## Sequence of [frequency, duration] sine notes with quick decay envelopes.
func _tone(notes: Array, amp: float, attack: float) -> AudioStreamWAV:
	var total := 0.0
	for n in notes:
		total += n[1]
	var frames := int(total * MIX_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var frame := 0
	for n in notes:
		var freq: float = n[0]
		var dur: float = n[1]
		var note_frames := int(dur * MIX_RATE)
		for i in note_frames:
			var t := float(i) / MIX_RATE
			var env := minf(t / attack, 1.0) * (1.0 - float(i) / note_frames)
			var v := sin(TAU * freq * t) * env * amp
			var s := int(clampf(v, -1.0, 1.0) * 32767.0)
			data.encode_s16(frame * 2, s)
			frame += 1
	return _wav(data, false)


## Low detuned hum + soft noise, seamless loop — the distant-engines bed.
func _make_ambient() -> AudioStreamWAV:
	var dur := 2.0
	var frames := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var noise_state := 12345
	var lp := 0.0
	for i in frames:
		var t := float(i) / MIX_RATE
		# Integer cycle counts over the loop keep the seam silent.
		var v := 0.20 * sin(TAU * 86.0 * t) + 0.14 * sin(TAU * 129.0 * t) \
				+ 0.08 * sin(TAU * 43.0 * t)
		noise_state = (noise_state * 1103515245 + 12345) & 0x7FFFFFFF
		var noise := (float(noise_state) / 0x3FFFFFFF - 1.0)
		lp += (noise - lp) * 0.08
		v += lp * 0.10
		v *= 0.9 + 0.1 * sin(TAU * 0.5 * t)
		var s := int(clampf(v, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	return _wav(data, true)


func _wav(data: PackedByteArray, looped: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = data.size() / 2
	return wav
