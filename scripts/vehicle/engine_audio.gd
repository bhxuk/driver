class_name EngineAudio
extends AudioStreamPlayer3D
## Procedural engine rumble and horn. No audio files needed.

const RATE := 22050.0

var rpm := 0.0       # 0..1
var throttle := 0.0  # 0..1
var horn := false
var volume := 1.0

var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _phase2 := 0.0
var _horn_a := 0.0
var _horn_b := 0.0
var _noise := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	stream = gen
	unit_size = 14.0
	max_distance = 160.0
	volume_db = -6.0
	play()
	_playback = get_stream_playback()


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var freq := lerpf(32.0, 105.0, clampf(rpm, 0.0, 1.0))
	var amp := (0.16 + throttle * 0.2) * volume
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in frames:
		_phase = fmod(_phase + freq / RATE, 1.0)
		_phase2 = fmod(_phase2 + freq * 0.5 / RATE, 1.0)
		var saw := _phase * 2.0 - 1.0
		var pulse := 1.0 if _phase2 < 0.3 else -0.6
		_noise = lerpf(_noise, _rng.randf_range(-1.0, 1.0), 0.15)
		var s := (saw * 0.45 + pulse * 0.35 + _noise * (0.15 + throttle * 0.25)) * amp
		if horn:
			_horn_a = fmod(_horn_a + 392.0 / RATE, 1.0)
			_horn_b = fmod(_horn_b + 494.0 / RATE, 1.0)
			s += ((1.0 if _horn_a < 0.5 else -1.0) + (1.0 if _horn_b < 0.5 else -1.0)) * 0.09 * volume
		buf[i] = Vector2(s, s)
	_playback.push_buffer(buf)
