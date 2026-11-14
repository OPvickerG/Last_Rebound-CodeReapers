extends Node
## LAST REBOUND: adaptive audio.
## The score is three synchronized stems (drone, pulse, strings). Layers join as you climb.
## Rain and wind are ambient; wind howls when you fall fast.

const SFX := {
	"great_bell": preload("res://audio/great_bell.wav"),
	"stone_hit": preload("res://audio/stone_hit.wav"),
	"slam": preload("res://audio/slam.wav"),
	"ignite": preload("res://audio/ignite.wav"),
	"respawn": preload("res://audio/respawn.wav"),
	"collapse": preload("res://audio/collapse.wav"),
	"title_hit": preload("res://audio/title_hit.wav"),
	"thunder_1": preload("res://audio/thunder_1.wav"),
	"thunder_2": preload("res://audio/thunder_2.wav"),
	"thunder_3": preload("res://audio/thunder_3.wav"),
}

var music_stream := AudioStreamSynchronized.new()
var music := AudioStreamPlayer.new()
var finale := AudioStreamPlayer.new()
var rain := AudioStreamPlayer.new()
var wind := AudioStreamPlayer.new()

## Target stem volumes in dB: drone, pulse, strings.
var targets := [-3.0, -60.0, -60.0]
var _current := [-60.0, -60.0, -60.0]
var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _wind_target := -40.0
var _master_music := 0.0


func _ready() -> void:
	# A limiter on the master bus keeps bell + thunder + finale from clipping.
	if AudioServer.get_bus_effect_count(0) == 0:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -1.0
		limiter.pre_gain_db = 0.0
		AudioServer.add_bus_effect(0, limiter)
	var stems := [
		preload("res://audio/music_drone.ogg"),
		preload("res://audio/music_pulse.ogg"),
		preload("res://audio/music_strings.ogg"),
	]
	music_stream.stream_count = stems.size()
	for i in stems.size():
		var s: AudioStreamOggVorbis = stems[i]
		s.loop = true
		music_stream.set_sync_stream(i, s)
		music_stream.set_sync_stream_volume(i, -60.0)
	music.stream = music_stream
	music.volume_db = -3.0
	add_child(music)

	finale.stream = preload("res://audio/music_finale.ogg")
	finale.volume_db = -4.0
	add_child(finale)

	rain.stream = _looped(preload("res://audio/rain_loop.wav"))
	rain.volume_db = -14.0
	add_child(rain)
	wind.stream = _looped(preload("res://audio/wind_loop.wav"))
	wind.volume_db = -40.0
	add_child(wind)

	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

	music.play()
	rain.play()
	wind.play()


func _looped(s: AudioStreamWAV) -> AudioStreamWAV:
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func _process(delta: float) -> void:
	for i in 3:
		_current[i] = move_toward(_current[i], targets[i] + _master_music, delta * 14.0)
		music_stream.set_sync_stream_volume(i, _current[i])
	wind.volume_db = move_toward(wind.volume_db, _wind_target, delta * 40.0)


## 0..1 for how much of the pulse and strings layers to bring in.
func set_intensity(pulse: float, strings: float) -> void:
	targets[1] = lerpf(-60.0, -1.5, clampf(pulse, 0, 1)) if pulse > 0.01 else -60.0
	targets[2] = lerpf(-60.0, -2.5, clampf(strings, 0, 1)) if strings > 0.01 else -60.0


func set_fall_speed(speed: float, gust: float = 0.0) -> void:
	var fall := clampf((speed - 10.0) / 26.0, 0.0, 1.0)
	_wind_target = lerpf(-34.0, -4.0, maxf(fall, clampf(gust, 0.0, 1.0)))


func play(sfx_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = SFX[sfx_name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func play_at(sfx_name: String, where: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = SFX[sfx_name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 10.0
	add_child(p)
	p.global_position = where
	p.finished.connect(p.queue_free)
	p.play()


func thunder(delay: float, volume_db: float) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(play.bind("thunder_%d" % randi_range(1, 3), volume_db, randf_range(0.85, 1.1)))


## Silence the score for a dramatic beat, then bring it back.
func duck(seconds: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_master_music", -30.0, 0.15)
	tw.tween_interval(seconds)
	tw.tween_property(self, "_master_music", 0.0, 2.0)


func to_finale() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(music, "volume_db", -60.0, 3.0)
	tw.tween_property(rain, "volume_db", -60.0, 6.0)
	tw.tween_property(wind, "volume_db", -60.0, 3.0)
	_wind_target = -60.0
	finale.play()
