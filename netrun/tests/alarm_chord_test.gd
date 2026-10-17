extends GdUnitTestSuite
## «Аккорд уровня» тревоги (ice.md §8: смена уровня тревоги узла — короткий аккорд): синтез в клиенте, без файлов звука. Чистая генерация AudioStreamWAV по уровню.


func test_нулевой_уровень_без_аккорда() -> void:
	assert_object(AlarmChord.make(0)).is_null()


func test_у_каждого_уровня_свой_аккорд_и_он_короткий() -> void:
	var seen := {}
	for level in range(1, 5):
		var wav := AlarmChord.make(level)
		assert_object(wav).is_not_null()
		assert_int(wav.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
		var secs := float(wav.data.size() / 2) / float(wav.mix_rate)
		assert_float(secs).is_between(0.3, 0.6)
		seen[hash(wav.data)] = true
	assert_int(seen.size()).is_equal(4)


func test_тоны_растут_с_уровнем_а_на_четвёртом_диссонанс() -> void:
	var lows: Array[float] = []
	for level in range(1, 4):
		lows.append((AlarmChord.tones(level) as Array)[0])
	assert_bool(lows[0] < lows[1] and lows[1] < lows[2]).override_failure_message("тоника по уровням %s" % str(lows)).is_true()
	var t4: Array = AlarmChord.tones(4)
	var close := false
	for i in t4.size():
		for j in range(i + 1, t4.size()):
			var ratio: float = maxf(t4[i], t4[j]) / minf(t4[i], t4[j])
			if ratio < 1.1:
				close = true   # малая секунда
	assert_bool(close).override_failure_message("на уровне 4 в аккорде должна быть малая секунда (диссонанс)").is_true()


func test_громкость_тихая_и_хвост_затухает() -> void:
	var wav := AlarmChord.make(2)
	var d := wav.data
	var peak := 0
	for i in range(0, d.size(), 2):
		peak = maxi(peak, absi(d.decode_s16(i)))
	assert_int(peak).is_less(int(32767 * 0.5))   # не громче половины шкалы: фоновый сигнал, как у остальных
	assert_int(peak).is_greater(1000)
	var tail := 0
	for i in range(d.size() - 200, d.size(), 2):
		tail = maxi(tail, absi(d.decode_s16(i)))
	assert_int(tail).is_less(peak / 10)


func test_клиент_играет_аккорд_на_новом_уровне_и_молчит_на_нулевом() -> void:
	var proto: ProtoClient = auto_free(ProtoClient.new())
	add_child(proto)
	proto._play_alarm_chord(0)
	assert_int(proto.chord_plays).is_equal(0)
	proto._play_alarm_chord(2)
	proto._play_alarm_chord(3)
	assert_int(proto.chord_plays).is_equal(2)
