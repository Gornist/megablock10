extends GdUnitTestSuite
## Кодек бинарных кадров голоса (shared/phone_voice_codec.gd, docs/netrun-phone-link.md, «Голос»): круг encode→decode, границы длины, перенос seq,
## образцы hex из tests/fixtures/phone_frames.json (раздел binary) — тем же файлом сверяется приложение.

const FRAMES_PATH := "res://tests/fixtures/phone_frames.json"


func _pcm(samples: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(samples.size() * 2)
	for i in samples.size():
		b.encode_s16(i * 2, int(samples[i]))
	return b


func _binary() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAMES_PATH))
	assert_bool(parsed is Dictionary).is_true()
	return (parsed as Dictionary)["binary"]


func test_roundtrip_keeps_type_seq_and_samples() -> void:
	var pcm := _pcm([0, 1, -1, 12345, -32768])
	for type in [PhoneVoiceCodec.TYPE_MIC, PhoneVoiceCodec.TYPE_PEER]:
		var bytes := PhoneVoiceCodec.encode(type, 42, pcm)
		assert_int(bytes.size()).is_equal(PhoneVoiceCodec.HEADER_BYTES + pcm.size())
		var d := PhoneVoiceCodec.decode(bytes)
		assert_bool(d["ok"]).is_true()
		assert_int(d["type"]).is_equal(type)
		assert_int(d["seq"]).is_equal(42)
		assert_array(d["pcm"]).is_equal(pcm)


func test_encode_rejects_empty_odd_oversized_and_unknown_type() -> void:
	assert_int(PhoneVoiceCodec.encode(PhoneVoiceCodec.TYPE_MIC, 0, PackedByteArray()).size()).is_equal(0)
	var odd := PackedByteArray([1, 2, 3])
	assert_int(PhoneVoiceCodec.encode(PhoneVoiceCodec.TYPE_MIC, 0, odd).size()).is_equal(0)
	var big := PackedByteArray()
	big.resize(PhoneVoiceCodec.MAX_PAYLOAD + 2)
	assert_int(PhoneVoiceCodec.encode(PhoneVoiceCodec.TYPE_MIC, 0, big).size()).is_equal(0)
	assert_int(PhoneVoiceCodec.encode(3, 0, _pcm([1])).size()).is_equal(0)
	# границы допустимого: 2 байта и ровно MAX_PAYLOAD
	assert_int(PhoneVoiceCodec.encode(PhoneVoiceCodec.TYPE_MIC, 0, _pcm([5])).size()).is_equal(PhoneVoiceCodec.HEADER_BYTES + 2)
	big.resize(PhoneVoiceCodec.MAX_PAYLOAD)
	assert_int(PhoneVoiceCodec.encode(PhoneVoiceCodec.TYPE_PEER, 0, big).size()).is_equal(PhoneVoiceCodec.HEADER_BYTES + PhoneVoiceCodec.MAX_PAYLOAD)


func test_decode_rejects_short_odd_oversized_and_unknown_type() -> void:
	var good := PhoneVoiceCodec.encode(PhoneVoiceCodec.TYPE_PEER, 1, _pcm([1, 2]))
	assert_bool(PhoneVoiceCodec.decode(PackedByteArray())["ok"]).is_false()
	assert_bool(PhoneVoiceCodec.decode(good.slice(0, 5))["ok"]).is_false()   # только заголовок
	assert_bool(PhoneVoiceCodec.decode(good.slice(0, 4))["ok"]).is_false()
	var odd := good.duplicate()
	odd.append(7)
	assert_bool(PhoneVoiceCodec.decode(odd)["ok"]).is_false()
	var unknown := good.duplicate()
	unknown[0] = 9
	assert_bool(PhoneVoiceCodec.decode(unknown)["ok"]).is_false()
	var zero := good.duplicate()
	zero[0] = 0
	assert_bool(PhoneVoiceCodec.decode(zero)["ok"]).is_false()
	var big := PackedByteArray([2, 0, 0, 0, 0])
	big.resize(PhoneVoiceCodec.HEADER_BYTES + PhoneVoiceCodec.MAX_PAYLOAD + 2)
	big[0] = 2
	assert_bool(PhoneVoiceCodec.decode(big)["ok"]).is_false()
	var d := PhoneVoiceCodec.decode(good.slice(0, 7))
	assert_bool(d["ok"]).is_true()
	assert_int(d["pcm"].size()).is_equal(2)


func test_seq_wraps_modulo_2_pow_32() -> void:
	var pcm := _pcm([1])
	assert_int(PhoneVoiceCodec.decode(PhoneVoiceCodec.encode(1, 4294967295, pcm))["seq"]).is_equal(4294967295)
	assert_int(PhoneVoiceCodec.decode(PhoneVoiceCodec.encode(1, 4294967296, pcm))["seq"]).is_equal(0)
	assert_int(PhoneVoiceCodec.decode(PhoneVoiceCodec.encode(1, 4294967297, pcm))["seq"]).is_equal(1)
	assert_int(PhoneVoiceCodec.decode(PhoneVoiceCodec.encode(1, -1, pcm))["seq"]).is_equal(4294967295)


func test_samples_per_chunk() -> void:
	assert_int(PhoneVoiceCodec.samples_per_chunk(44100)).is_equal(882)
	assert_int(PhoneVoiceCodec.samples_per_chunk(8000)).is_equal(160)
	assert_int(PhoneVoiceCodec.samples_per_chunk(48000, 10)).is_equal(480)
	assert_int(PhoneVoiceCodec.samples_per_chunk(44100) * 2).is_less_equal(PhoneVoiceCodec.MAX_PAYLOAD)


func test_documented_hex_samples_decode_and_reencode_exactly() -> void:
	var b := _binary()
	var expected := _pcm(b["samples"])
	var seq := int(b["seq"])
	for pair in [["voice_mic_hex", PhoneVoiceCodec.TYPE_MIC], ["voice_peer_hex", PhoneVoiceCodec.TYPE_PEER]]:
		var bytes := str(b[pair[0]]).hex_decode()
		var d := PhoneVoiceCodec.decode(bytes)
		assert_bool(d["ok"]).is_true()
		assert_int(d["type"]).is_equal(pair[1])
		assert_int(d["seq"]).is_equal(seq)
		assert_array(d["pcm"]).is_equal(expected)
		assert_array(PhoneVoiceCodec.encode(pair[1], seq, expected)).is_equal(bytes)
