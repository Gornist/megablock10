extends GdUnitTestSuite
## Чистая обработка звука голоса (shared/phone_voice_dsp.gd): моно, ресемплинг, int16, громкость, тишина.


func _sine(n: int, rate: int, hz: float, amp: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = amp * sin(TAU * hz * float(i) / float(rate))
	return out


func _peak(a: PackedFloat32Array) -> float:
	var p := 0.0
	for v in a:
		p = maxf(p, absf(v))
	return p


func test_stereo_to_mono_averages_the_channels() -> void:
	var mono := PhoneVoiceDsp.stereo_to_mono_float(PackedVector2Array([Vector2(1.0, 0.0), Vector2(0.5, -0.5), Vector2(-0.25, -0.75)]))
	assert_int(mono.size()).is_equal(3)
	assert_float(mono[0]).is_equal_approx(0.5, 0.0001)
	assert_float(mono[1]).is_equal_approx(0.0, 0.0001)
	assert_float(mono[2]).is_equal_approx(-0.5, 0.0001)
	assert_int(PhoneVoiceDsp.stereo_to_mono_float(PackedVector2Array()).size()).is_equal(0)


func test_float_to_pcm16_to_stereo_roundtrip() -> void:
	var src := PackedFloat32Array([0.0, 0.5, -0.5, 0.25, -1.0])
	var pcm := PhoneVoiceDsp.float_to_pcm16(src)
	assert_int(pcm.size()).is_equal(10)
	var st := PhoneVoiceDsp.pcm16_to_stereo(pcm)
	assert_int(st.size()).is_equal(5)
	for i in src.size():
		assert_float(st[i].x).is_equal_approx(src[i], 0.001)
		assert_float(st[i].y).is_equal_approx(src[i], 0.001)   # моно в оба канала


func test_float_to_pcm16_clips_to_full_scale() -> void:
	var pcm := PhoneVoiceDsp.float_to_pcm16(PackedFloat32Array([2.0, -3.0, 1.0, -1.0]))
	assert_int(pcm.decode_s16(0)).is_equal(32767)
	assert_int(pcm.decode_s16(2)).is_equal(-32767)
	assert_int(pcm.decode_s16(4)).is_equal(32767)
	assert_int(pcm.decode_s16(6)).is_equal(-32767)


func test_resample_same_rate_is_a_copy() -> void:
	var src := _sine(100, 44100, 440.0, 0.5)
	var out := PhoneVoiceDsp.resample_linear(src, 44100, 44100)
	assert_array(out).is_equal(src)
	out[0] = 9.0
	assert_float(src[0]).is_not_equal(9.0)   # копия, не тот же массив


func test_resample_48000_to_44100_changes_the_length_and_keeps_amplitude() -> void:
	var n := 4800
	var src := _sine(n, 48000, 440.0, 0.8)
	var out := PhoneVoiceDsp.resample_linear(src, 48000, 44100)
	assert_int(out.size()).is_equal(int(round(n * 44100.0 / 48000.0)))
	assert_float(_peak(out)).is_equal_approx(0.8, 0.02)
	# Тон на месте: отсчёты совпадают с синусом новой частоты (линейная интерполяция гладкого 440 Гц — ошибка ≪ 1 %).
	var ref := _sine(out.size(), 44100, 440.0, 0.8)
	for i in range(10, out.size() - 10, 37):
		assert_float(out[i]).is_equal_approx(ref[i], 0.01)


func test_resample_upsamples_and_handles_empty() -> void:
	var out := PhoneVoiceDsp.resample_linear(PackedFloat32Array([0.0, 1.0]), 8000, 16000)
	assert_int(out.size()).is_equal(4)
	assert_float(out[1]).is_equal_approx(0.5, 0.0001)
	assert_int(PhoneVoiceDsp.resample_linear(PackedFloat32Array(), 48000, 44100).size()).is_equal(0)
	assert_int(PhoneVoiceDsp.resample_linear(PackedFloat32Array([1.0]), 0, 44100).size()).is_equal(0)


func test_rms_of_silence_and_full_scale() -> void:
	assert_float(PhoneVoiceDsp.rms_pcm16(PhoneVoiceDsp.silence_pcm16(100))).is_equal(0.0)
	var full := PackedByteArray()
	full.resize(200)
	for i in 100:
		full.encode_s16(i * 2, -32768 if i % 2 == 0 else 32767)
	assert_float(PhoneVoiceDsp.rms_pcm16(full)).is_equal_approx(1.0, 0.001)
	assert_float(PhoneVoiceDsp.rms_pcm16(PackedByteArray())).is_equal(0.0)


func test_rms_of_a_half_amplitude_sine() -> void:
	var pcm := PhoneVoiceDsp.float_to_pcm16(_sine(4410, 44100, 441.0, 0.5))
	assert_float(PhoneVoiceDsp.rms_pcm16(pcm)).is_equal_approx(0.5 / sqrt(2.0), 0.005)


func test_odd_pcm_length_drops_the_last_byte() -> void:
	var pcm := PackedByteArray()
	pcm.resize(5)
	pcm.encode_s16(0, 16384)
	pcm.encode_s16(2, -16384)
	pcm[4] = 0xFF
	assert_int(PhoneVoiceDsp.pcm16_to_stereo(pcm).size()).is_equal(2)
	assert_float(PhoneVoiceDsp.rms_pcm16(pcm)).is_equal_approx(0.5, 0.001)


func test_silence_has_the_requested_length_in_zero_bytes() -> void:
	var s := PhoneVoiceDsp.silence_pcm16(882)
	assert_int(s.size()).is_equal(1764)
	for b in s:
		assert_int(b).is_equal(0)
	assert_int(PhoneVoiceDsp.silence_pcm16(-5).size()).is_equal(0)
