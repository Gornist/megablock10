class_name IceAudio
extends Node3D
## Пространственный звук ICE: AudioStreamPlayer3D на самом ICE. Громкость и тон — из AudioParams
## (расстояние до слушателя и состояние); панорама и направление — от самого AudioStreamPlayer3D.

var settings: Dictionary
var state := 0  ## IceBrain.State

var _player: AudioStreamPlayer3D
var _synth: ToneSynth
var _playback: AudioStreamGeneratorPlayback


func _init(custom: Dictionary = {}) -> void:
	settings = AudioSettings.merged(custom)


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = settings["sample_rate"]
	gen.buffer_length = 0.15
	_synth = ToneSynth.new(gen.mix_rate)
	_synth.noise = 0.1
	_synth.mod_depth = 0.4
	_player = AudioStreamPlayer3D.new()
	_player.stream = gen
	_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED  # расстояние считаем сами (настройками)
	_player.max_distance = 0.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	_update()


func set_state(new_state: int) -> void:
	state = new_state
	_update()


## Расстояние до слушателя: активная камера, иначе 0 (вне дерева/без камеры).
func listener_distance() -> float:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return global_position.distance_to(cam.global_position) if cam != null else 0.0


func _update() -> void:
	if _synth == null:
		return
	var p := AudioParams.ice_params(state, listener_distance(), settings)
	_player.volume_db = p["volume_db"] if p["audible"] else -80.0
	_synth.hz = p["base_hz"]
	_synth.mod_hz = p["warble_hz"]


func _process(_delta: float) -> void:
	if _playback != null:
		_update()
		_synth.fill(_playback)
