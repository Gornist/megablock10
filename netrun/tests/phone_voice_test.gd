extends GdUnitTestSuite
## Узел голоса телефона (client/phone_voice.gd): включение по `voice_requested`, поток кусков микрофона, дуплексное приглушение, приём звука собеседника.
## Связь и звуковой сервер подменены: ни сокета, ни микрофона.

const RATE := 44100
const CHUNK_BYTES := 882 * 2   # 20 мс при 44100 Гц, int16


class FakeLink extends RemotePhoneLink:
	var ready_calls: Array[bool] = []
	var chunks: Array[PackedByteArray] = []

	func send_voice_ready(on: bool) -> void:
		ready_calls.append(on)

	func send_voice_chunk(pcm: PackedByteArray) -> bool:
		chunks.append(pcm)
		return true


class FakeVoice extends PhoneVoice:
	var permission := true
	var input_available := true
	var input_closed := 0
	var queue: PackedVector2Array = PackedVector2Array()     # что «накопил микрофон»
	var capacity := 8820                                     # 0,2 с при 44100
	var played := 0                                          # кадров в очереди воспроизведения

	func _permission_ok() -> bool:
		return permission

	func _input_ready() -> bool:
		return input_available

	func _input_close() -> void:
		input_closed += 1

	func _input_rate() -> int:
		return 44100

	func _pull_input(max_frames: int) -> PackedVector2Array:
		var n := mini(queue.size(), max_frames)
		var out := queue.slice(0, n)
		queue = queue.slice(n)
		return out

	func _playback_free_frames() -> int:
		return capacity - played

	func _playback_push(stereo: PackedVector2Array) -> void:
		played += stereo.size()


func _link() -> FakeLink:
	return FakeLink.new()


func _voice(link: FakeLink) -> FakeVoice:
	var v: FakeVoice = auto_free(FakeVoice.new())
	add_child(v)
	v.bind(link)
	return v


func _loud(samples: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(samples)
	for i in samples:
		var s := 0.5 * sin(TAU * 440.0 * float(i) / float(RATE))
		out[i] = Vector2(s, s)
	return out


func _peer_pcm(samples: int, amp: float) -> PackedByteArray:
	var m := PackedFloat32Array()
	m.resize(samples)
	for i in samples:
		m[i] = amp * sin(TAU * 440.0 * float(i) / float(RATE))
	return PhoneVoiceDsp.float_to_pcm16(m)


func _all_zero(pcm: PackedByteArray) -> bool:
	for b in pcm:
		if b != 0:
			return false
	return true


func _start(link: FakeLink, v: FakeVoice) -> void:
	link.voice_requested.emit(true, RATE)
	assert_bool(v.is_active()).is_true()


# ---------------------------------------------------------------- включение

func test_voice_on_opens_input_and_answers_ready_once() -> void:
	var link := _link()
	var v := _voice(link)
	var reasons: Array[String] = []
	v.ready_sent.connect(func(on: bool, reason: String): reasons.append("%s:%s" % [on, reason]))
	link.voice_requested.emit(true, RATE)
	assert_bool(v.is_active()).is_true()
	assert_array(link.ready_calls).is_equal([true])
	assert_array(reasons).is_equal(["true:ok"])
	assert_int(v.stats()["rate"]).is_equal(RATE)


func test_no_permission_answers_not_ready_and_stays_off() -> void:
	var link := _link()
	var v := _voice(link)
	v.permission = false
	var reasons: Array[String] = []
	v.ready_sent.connect(func(on: bool, reason: String): reasons.append("%s:%s" % [on, reason]))
	link.voice_requested.emit(true, RATE)
	assert_bool(v.is_active()).is_false()
	assert_array(link.ready_calls).is_equal([false])
	assert_array(reasons).is_equal(["false:no_permission"])


func test_no_input_device_answers_not_ready() -> void:
	var link := _link()
	var v := _voice(link)
	v.input_available = false
	link.voice_requested.emit(true, RATE)
	assert_bool(v.is_active()).is_false()
	assert_array(link.ready_calls).is_equal([false])


func test_voice_off_stops_without_answering() -> void:
	var link := _link()
	var v := _voice(link)
	_start(link, v)
	link.voice_requested.emit(false, RATE)
	assert_bool(v.is_active()).is_false()
	assert_int(v.input_closed).is_equal(1)
	assert_array(link.ready_calls).is_equal([true])   # ничего нового после выключения
	v.advance(0.1)
	assert_int(link.chunks.size()).is_equal(0)


func test_rebind_unsubscribes_the_previous_link_and_stops_voice() -> void:
	var first := _link()
	var second := _link()
	var v := _voice(first)
	_start(first, v)
	v.bind(second)
	assert_bool(v.is_active()).is_false()
	first.voice_requested.emit(true, RATE)
	assert_bool(v.is_active()).is_false()
	assert_int(first.ready_calls.size()).is_equal(1)
	second.voice_requested.emit(true, RATE)
	assert_bool(v.is_active()).is_true()
	assert_array(second.ready_calls).is_equal([true])
	v.bind(null)
	assert_bool(v.is_active()).is_false()


# ---------------------------------------------------------------- микрофон

func test_chunks_flow_every_20_ms_with_exact_size_even_with_empty_input() -> void:
	var link := _link()
	var v := _voice(link)
	_start(link, v)
	for i in 10:
		v.advance(0.02)
	assert_int(link.chunks.size()).is_equal(10)
	for c in link.chunks:
		assert_int(c.size()).is_equal(CHUNK_BYTES)
		assert_bool(_all_zero(c)).is_true()   # входа нет — нули, но поток не рвётся
	assert_int(v.stats()["sent"]).is_equal(10)


func test_real_samples_go_out_and_the_gap_is_padded_with_zeros() -> void:
	var link := _link()
	var v := _voice(link)
	_start(link, v)
	v.queue = _loud(882 + 300)
	v.advance(0.02)
	v.advance(0.02)
	assert_int(link.chunks.size()).is_equal(2)
	assert_float(PhoneVoiceDsp.rms_pcm16(link.chunks[0])).is_greater(0.2)
	assert_int(link.chunks[1].size()).is_equal(CHUNK_BYTES)
	var tail := link.chunks[1].slice(300 * 2)
	assert_bool(_all_zero(tail)).is_true()
	assert_float(PhoneVoiceDsp.rms_pcm16(link.chunks[1].slice(0, 300 * 2))).is_greater(0.2)


func test_a_stalled_frame_sends_at_most_five_chunks() -> void:
	var link := _link()
	var v := _voice(link)
	_start(link, v)
	v.advance(1.0)
	assert_int(link.chunks.size()).is_equal(PhoneVoice.MAX_CHUNKS_PER_TICK)
	v.advance(0.02)
	assert_int(link.chunks.size()).is_equal(PhoneVoice.MAX_CHUNKS_PER_TICK + 1)   # лишнее время не копится долгом


func test_mic_backlog_is_capped() -> void:
	var link := _link()
	var v := _voice(link)
	_start(link, v)
	v.queue = _loud(RATE)   # секунда накопленного входа
	v.advance(0.0)
	assert_int(v.stats()["mic_dropped"]).is_greater(0)


# ---------------------------------------------------------------- приглушение

func test_loud_peer_ducks_the_microphone_and_releases_after_the_hold() -> void:
	var link := _link()
	var v := _voice(link)
	_start(link, v)
	link.voice_frame_received.emit(0, _peer_pcm(882, 0.5))
	v.queue = _loud(RATE / 10)
	v.advance(0.02)
	assert_bool(_all_zero(link.chunks[0])).is_true()
	assert_int(v.stats()["ducked_ms"]).is_equal(PhoneVoice.CHUNK_MS)
	# Собеседник замолчал: ещё DUCK_HOLD_MS микрофон молчит, потом возвращается.
	var ticks := int(ceil(float(PhoneVoice.DUCK_HOLD_MS) / 20.0))
	for i in ticks:
		v.advance(0.02)
	v.queue = _loud(RATE / 10)
	v.advance(0.02)
	assert_float(PhoneVoiceDsp.rms_pcm16(link.chunks[link.chunks.size() - 1])).is_greater(0.2)


func test_quiet_peer_does_not_duck() -> void:
	var link := _link()
	var v := _voice(link)
	_start(link, v)
	link.voice_frame_received.emit(0, _peer_pcm(882, 0.005))
	v.queue = _loud(RATE / 10)
	v.advance(0.02)
	assert_float(PhoneVoiceDsp.rms_pcm16(link.chunks[0])).is_greater(0.2)
	assert_int(v.stats()["ducked_ms"]).is_equal(0)


# ---------------------------------------------------------------- звук собеседника

func test_peer_frames_play_and_count() -> void:
	var link := _link()
	var v := _voice(link)
	_start(link, v)
	link.voice_frame_received.emit(5, _peer_pcm(882, 0.1))
	link.voice_frame_received.emit(6, _peer_pcm(882, 0.1))
	assert_int(v.played).is_equal(882 * 2)
	assert_int(v.stats()["received"]).is_equal(2)


func test_duplicates_and_late_frames_are_dropped_and_losses_counted() -> void:
	var link := _link()
	var v := _voice(link)
	_start(link, v)
	var pcm := _peer_pcm(100, 0.1)
	link.voice_frame_received.emit(10, pcm)
	link.voice_frame_received.emit(10, pcm)    # дубль
	link.voice_frame_received.emit(14, pcm)    # потеряны 11, 12, 13
	link.voice_frame_received.emit(12, pcm)    # поздний
	var st := v.stats()
	assert_int(st["received"]).is_equal(2)
	assert_int(st["late"]).is_equal(2)
	assert_int(st["lost"]).is_equal(3)
	assert_int(v.played).is_equal(200)


func test_seq_wrap_around_is_not_late() -> void:
	var link := _link()
	var v := _voice(link)
	_start(link, v)
	var pcm := _peer_pcm(100, 0.1)
	link.voice_frame_received.emit(0xFFFFFFFE, pcm)
	link.voice_frame_received.emit(0xFFFFFFFF, pcm)
	link.voice_frame_received.emit(0, pcm)
	link.voice_frame_received.emit(1, pcm)
	var st := v.stats()
	assert_int(st["received"]).is_equal(4)
	assert_int(st["late"]).is_equal(0)
	assert_int(st["lost"]).is_equal(0)


func test_full_playback_queue_drops_frames_instead_of_growing() -> void:
	var link := _link()
	var v := _voice(link)
	_start(link, v)
	var pcm := _peer_pcm(882, 0.1)
	for seq in 40:   # 40 × 20 мс = 0,8 с при ёмкости 0,2 с
		link.voice_frame_received.emit(seq, pcm)
	assert_int(v.played).is_less_equal(v.capacity)
	assert_int(v.stats()["overflow"]).is_greater(0)
	assert_int(v.stats()["received"]).is_equal(40)


func test_peer_frames_are_ignored_while_off() -> void:
	var link := _link()
	var v := _voice(link)
	link.voice_frame_received.emit(0, _peer_pcm(100, 0.1))
	assert_int(v.played).is_equal(0)
	assert_int(v.stats()["received"]).is_equal(0)


func test_a_new_session_restarts_the_sequence_and_the_counters() -> void:
	var link := _link()
	var v := _voice(link)
	_start(link, v)
	link.voice_frame_received.emit(500, _peer_pcm(100, 0.1))
	link.voice_requested.emit(false, RATE)
	link.voice_requested.emit(true, RATE)
	link.voice_frame_received.emit(0, _peer_pcm(100, 0.1))   # seq с нуля — не «поздний»
	assert_int(v.stats()["received"]).is_equal(1)
	assert_int(v.stats()["late"]).is_equal(0)
