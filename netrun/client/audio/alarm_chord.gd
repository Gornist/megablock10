class_name AlarmChord
extends RefCounted
## «Аккорд уровня» тревоги узла (ice.md §8: смена поведения всегда со звуком; тревога — «короткий аккорд уровня»): ≈0,4 с, синтез в клиенте без файлов.
## Выше уровень — выше тоника и теснее интервалы: 1 — пустая квинта, 2 — минор, 3 — уменьшенный, 4 (локдаун) — диссонанс с малой секундой. Громкость тихая, как у остальных сигналов.

const RATE := 22050
const SECONDS := 0.4
const GAIN := 0.3        ## пик ≈ 0,3 шкалы на четыре тона слабее: огибающая и нормировка по числу тонов
const ATTACK_S := 0.015
const DECAY_PER_S := 7.0  ## экспонента затухания хвоста: к концу ≈ e^-2,8 ≈ 6 %

## Тоны по уровню 1…4, Гц.
const TONES := {
	1: [220.0, 329.6],
	2: [261.6, 311.1, 392.0],
	3: [293.7, 349.2, 415.3],
	4: [196.0, 207.7, 277.2, 392.0],
}


## Частоты аккорда уровня; пусто для уровня вне 1…4.
static func tones(level: int) -> Array:
	return (TONES.get(level, []) as Array).duplicate()


## Аккорд уровня как AudioStreamWAV (16 бит, моно); null — для уровня 0 и вне диапазона (спокойно: звука нет).
static func make(level: int, rate: int = RATE) -> AudioStreamWAV:
	var freqs := tones(level)
	if freqs.is_empty():
		return null
	var n := int(SECONDS * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := minf(t / ATTACK_S, 1.0) * exp(-DECAY_PER_S * t)
		var v := 0.0
		for f: float in freqs:
			v += sin(TAU * f * t)
		v = v / freqs.size() * GAIN * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
