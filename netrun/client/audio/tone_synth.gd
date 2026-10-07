class_name ToneSynth
extends RefCounted
## Синтез в AudioStreamGenerator: тон с модуляцией громкости (пульс/подрагивание) и лёгкой шумовой подложкой.
## Узел-хозяин зовёт fill() из _process; параметры можно менять на лету.

var hz := 110.0
var mod_hz := 0.0
var mod_depth := 0.0
var noise := 0.05
## Общая громкость 0..1 поверх всего: короткие звуки (щелчки такта) гасят ею хвост на лету; для гула остаётся 1.
var gain := 1.0

var _phase := 0.0
var _mod_phase := 0.0
var _rate: float


func _init(sample_rate: float) -> void:
	_rate = sample_rate


## Заполняет свободное место в буфере воспроизведения. Возвращает число записанных кадров.
func fill(playback: AudioStreamGeneratorPlayback) -> int:
	var n := playback.get_frames_available()
	for _i in n:
		var env := 1.0 - mod_depth * (0.5 + 0.5 * sin(_mod_phase))
		var v := (sin(_phase) * 0.8 + randf_range(-1.0, 1.0) * noise) * env * gain
		playback.push_frame(Vector2(v, v))
		_phase = fmod(_phase + TAU * hz / _rate, TAU)
		_mod_phase = fmod(_mod_phase + TAU * mod_hz / _rate, TAU)
	return n
