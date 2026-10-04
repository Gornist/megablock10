extends GdUnitTestSuite
## Отклик деки (DeckFeedback): импульс левого контроллера и сигнал на входящее сообщение, серия импульсов и рингтон на входящий звонок.
## Контроллеров и звука на машине нет — импульсы идут в pulse_sink; главное, что без вибрации и звука всё молча проходит.

const T0 := 1_700_000_000.0

var _fb: DeckFeedback
var _link: FakePhoneLink
var _pulses: Array


func _setup() -> void:
	_fb = auto_free(DeckFeedback.new())
	add_child(_fb)
	_link = FakePhoneLink.new(T0, false)
	_link.auto_reply = false
	_pulses = []
	_fb.pulse_sink = func(hand: String, amp: float, sec: float): _pulses.append([hand, amp, sec])
	_fb.bind(null, _link)


func test_ring_pulse_times_are_bursts_of_three_every_period() -> void:
	var t := []
	for i in 7:
		t.append(snappedf(DeckFeedback.ring_pulse_time(i), 0.001))
	assert_array(t).is_equal([0.0, 0.22, 0.44, 2.2, 2.42, 2.64, 4.4])


func test_incoming_message_gives_a_short_pulse_on_the_left_hand_and_a_beep() -> void:
	_setup()
	_link.receive_message(FakePhoneLink.ID_VOBLA, "ВОБЛА", "Эй")
	assert_int(_pulses.size()).is_equal(1)
	assert_str(_pulses[0][0]).is_equal("left")
	assert_float(_pulses[0][2]).is_less_equal(0.1)   # короткий
	assert_int(_fb.message_beeps).is_equal(1)


func test_own_message_does_not_vibrate() -> void:
	_setup()
	_link.send_text(FakePhoneLink.ID_VOBLA, "ОК")
	assert_int(_pulses.size()).is_equal(0)
	assert_int(_fb.message_beeps).is_equal(0)


func test_incoming_call_rings_with_bursts_until_answered() -> void:
	_setup()
	_link.incoming_call("ВОБЛА")
	assert_bool(_fb.is_ringing()).is_true()
	assert_int(_pulses.size()).is_equal(1)   # первый импульс сразу
	_fb._step_ring(0.5)
	assert_int(_pulses.size()).is_equal(3)   # серия из трёх
	_fb._step_ring(2.0)   # 2,5 с от начала: началась вторая серия
	assert_int(_pulses.size()).is_equal(5)
	for p in _pulses:
		assert_str(p[0]).is_equal("left")
		assert_float(p[1]).is_greater(0.3)   # звонок заметнее сообщения
	_link.accept_call()
	assert_bool(_fb.is_ringing()).is_false()
	assert_int(_fb.ring_starts).is_equal(1)


func test_declined_or_missed_call_stops_the_ring() -> void:
	_setup()
	_link.incoming_call("ЛИС")
	_link.decline_call()
	assert_bool(_fb.is_ringing()).is_false()
	_link.incoming_call("ЛИС")
	assert_bool(_fb.is_ringing()).is_true()
	_link.advance(FakePhoneLink.RING_TIMEOUT_S + 1.0)
	assert_bool(_fb.is_ringing()).is_false()


func test_outgoing_call_does_not_ring() -> void:
	_setup()
	_link.start_call("ВОБЛА")
	assert_bool(_fb.is_ringing()).is_false()
	assert_int(_pulses.size()).is_equal(0)


func test_answered_and_finished_calls_give_a_short_confirmation() -> void:
	_setup()
	_link.start_call("ВОБЛА")
	_link.advance(FakePhoneLink.ANSWER_AFTER_S["ВОБЛА"] + 0.1)   # ответили
	assert_int(_pulses.size()).is_equal(1)
	_link.hangup()
	assert_int(_pulses.size()).is_equal(2)


func test_everything_is_silent_without_a_headset() -> void:
	# Без sink, без очков и без рига: импульс только считается, ошибок нет.
	var fb: DeckFeedback = auto_free(DeckFeedback.new())
	add_child(fb)
	var link := FakePhoneLink.new(T0, false)
	fb.bind(null, link)
	link.receive_message(FakePhoneLink.ID_VOBLA, "ВОБЛА", "Эй")
	link.incoming_call("ВОБЛА")
	link.accept_call()
	assert_int(fb.pulse_count).is_greater(0)


func test_tone_streams_are_16_bit_mono_with_the_expected_length() -> void:
	var msg := DeckFeedback.make_tone_stream(DeckFeedback.MESSAGE_NOTES, 0.02, 0.0, false)
	assert_int(msg.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
	assert_bool(msg.stereo).is_false()
	var expect := int((0.07 + 0.02 + 0.09 + 0.02) * DeckFeedback.SAMPLE_RATE)
	assert_int(msg.data.size() / 2).is_between(expect - 3, expect + 3)   # длительности тонов округляются до кадра
	assert_int(msg.loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)
	var ring := DeckFeedback.make_tone_stream(DeckFeedback.RING_NOTES, 0.05, DeckFeedback.RING_PERIOD_S, true)
	assert_int(ring.data.size() / 2).is_equal(int(DeckFeedback.RING_PERIOD_S * DeckFeedback.SAMPLE_RATE))
	assert_int(ring.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(ring.loop_end).is_equal(ring.data.size() / 2)


func test_tone_is_not_silent_and_never_clips() -> void:
	var s := DeckFeedback.make_tone_stream([[880.0, 0.1]], 0.0, 0.0, false)
	var peak := 0
	for i in range(0, s.data.size(), 2):
		peak = maxi(peak, absi(s.data.decode_s16(i)))
	assert_int(peak).is_greater(3000)
	assert_int(peak).is_less(32767)
