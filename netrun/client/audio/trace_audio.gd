class_name TraceAudio
extends Node
## Фоновый звук trace: ровный гул, который с уровнем становится громче, выше и пульсирует чаще;
## на FLATLINE фон исчезает (сильнейший сигнал — пропажа фона, docs/netrun.md).

## Уровень FLATLINE = TraceMeter.Level.FLATLINE (уровни приходят числом в снимке): server/ в APK очков нет, номер продублирован,
## совпадение стережёт tests/client_export_test.gd.
const FLATLINE := 4

var settings: Dictionary
var level := 0

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
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	set_level(level)


func set_level(new_level: int) -> void:
	level = new_level
	if _synth == null:
		return
	var p := AudioParams.trace_params(level, settings)
	_player.volume_db = p["volume_db"]
	_synth.hz = p["base_hz"]
	_synth.mod_hz = p["pulse_hz"]
	_synth.mod_depth = p["pulse_depth"]


func _process(_delta: float) -> void:
	if _playback != null:
		_synth.fill(_playback)
