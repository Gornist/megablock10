class_name FlatlineAudio
extends Node
## Звук флэтлайна: падающий тон и тишина (AudioParams.flatline_params). Один раз, сам убирается. Только звук, без движения камеры.

var settings: Dictionary
var elapsed := 0.0

var _player: AudioStreamPlayer
var _synth: ToneSynth
var _playback: AudioStreamGeneratorPlayback


func _init(custom: Dictionary = {}) -> void:
	settings = AudioSettings.merged(custom)


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = settings["sample_rate"]
	gen.buffer_length = 0.15
	_synth = ToneSynth.new(gen.mix_rate)
	_synth.noise = 0.02
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()


func _process(delta: float) -> void:
	elapsed += delta
	var p := AudioParams.flatline_params(elapsed, settings)
	if not p["active"]:
		queue_free()
		return
	_player.volume_db = p["volume_db"]
	_synth.hz = p["hz"]
	_synth.fill(_playback)
