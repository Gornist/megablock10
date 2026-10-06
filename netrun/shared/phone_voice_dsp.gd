class_name PhoneVoiceDsp
extends RefCounted
## Чистая обработка звука для голоса телефона (client/phone_voice.gd): вход микрофона Godot (стерео float, частота ОС) → моно int16 на частоте
## связи, и обратно звук собеседника (моно int16) → стерео для AudioStreamGenerator. Ни узлов, ни сервера звука — только массивы.


## Моно из стерео: среднее левого и правого канала.
static func stereo_to_mono_float(frames: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames.size())
	for i in frames.size():
		var f := frames[i]
		out[i] = (f.x + f.y) * 0.5
	return out


## Линейная передискретизация. Равные частоты — копия; пустой вход или частота ≤ 0 — пустой массив.
## Длина выхода = round(n·to/from). Состояния между кусками нет: на стыках кусков возможен скачок на долю отсчёта, для речи он незаметен.
static func resample_linear(mono: PackedFloat32Array, from_rate: int, to_rate: int) -> PackedFloat32Array:
	if mono.is_empty() or from_rate <= 0 or to_rate <= 0:
		return PackedFloat32Array()
	if from_rate == to_rate:
		return mono.duplicate()
	var n_out := int(round(float(mono.size()) * float(to_rate) / float(from_rate)))
	var out := PackedFloat32Array()
	out.resize(n_out)
	var step := float(from_rate) / float(to_rate)
	var last := mono.size() - 1
	for i in n_out:
		var pos := float(i) * step
		var i0 := mini(int(pos), last)
		var i1 := mini(i0 + 1, last)
		var frac := pos - float(i0)
		out[i] = mono[i0] + (mono[i1] - mono[i0]) * frac
	return out


## Моно float (клип в −1…1) → int16 LE.
static func float_to_pcm16(mono: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(mono.size() * 2)
	for i in mono.size():
		out.encode_s16(i * 2, int(round(clampf(mono[i], -1.0, 1.0) * 32767.0)))
	return out


## Моно int16 LE → стерео (один отсчёт в оба канала). Нечётный последний байт отбрасывается.
static func pcm16_to_stereo(pcm: PackedByteArray) -> PackedVector2Array:
	var n := pcm.size() >> 1
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var v := float(pcm.decode_s16(i * 2)) / 32768.0
		out[i] = Vector2(v, v)
	return out


## Среднеквадратичная громкость куска int16 LE: 0 (тишина) … 1 (полная амплитуда). Нечётный последний байт отбрасывается.
static func rms_pcm16(pcm: PackedByteArray) -> float:
	var n := pcm.size() >> 1
	if n == 0:
		return 0.0
	var sum := 0.0
	for i in n:
		var v := float(pcm.decode_s16(i * 2)) / 32768.0
		sum += v * v
	return sqrt(sum / float(n))


## Тишина: `samples` нулевых отсчётов int16 (байты уже нулевые после resize).
static func silence_pcm16(samples: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(maxi(samples, 0) * 2)
	return out
