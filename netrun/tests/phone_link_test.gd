extends GdUnitTestSuite
## Фиктивная связь с телефоном (FakePhoneLink): начальные диалоги, сценарий на часах advance(), отправка заготовки и звонок
## «как в CallManager» — входящий (принять / отклонить / не взяли), исходящий (ответили / отмена / не в сети), занятая линия,
## заглушение, журнал. Часы не настоящие: тест двигает их сам, поэтому всё детерминировано.

const T0 := 1_700_000_000.0


func _link(scenario: bool = false) -> FakePhoneLink:
	var l := FakePhoneLink.new(T0, scenario)
	l.auto_reply = false
	return l


func _thread_of(link: PhoneLink, id: String) -> Dictionary:
	for t in link.threads():
		if t["id"] == id:
			return t
	return {}


func test_base_link_is_a_safe_empty_phone() -> void:
	var l := PhoneLink.new()
	assert_array(l.threads()).is_empty()
	assert_array(l.messages("x", 8)).is_empty()
	assert_array(l.call_log()).is_empty()
	assert_str(l.call_state()["phase"]).is_equal(PhoneLink.PHASE_IDLE)
	l.send_text("x", "ОК")   # ничего не делают и не падают
	l.accept_call()
	l.start_call("ВОБЛА")


func test_starts_with_four_threads_one_of_them_faction() -> void:
	var l := _link()
	var kinds := {}
	for t in l.threads():
		kinds[t["kind"]] = int(kinds.get(t["kind"], 0)) + 1
		for key in ["id", "kind", "title", "last_text", "last_ts", "unread"]:
			assert_bool(t.has(key)).is_true()
	assert_int(l.threads().size()).is_equal(4)
	assert_int(kinds[PhoneLink.KIND_FACTION]).is_equal(1)
	assert_int(kinds[PhoneLink.KIND_DM]).is_equal(3)
	assert_int(PhoneLogic.unread_total(l.threads())).is_equal(1)   # на старте у чата уже есть бейдж


func test_messages_returns_last_n_oldest_first() -> void:
	var l := _link()
	var all := l.messages(FakePhoneLink.ID_VOBLA, 8)
	assert_int(all.size()).is_equal(3)
	assert_bool(all[0]["ts"] < all[2]["ts"]).is_true()
	var two := l.messages(FakePhoneLink.ID_VOBLA, 2)
	assert_int(two.size()).is_equal(2)
	assert_str(two[1]["text"]).is_equal(all[2]["text"])
	assert_array(l.messages("нет такого", 8)).is_empty()
	assert_array(l.messages(FakePhoneLink.ID_VOBLA, 0)).is_empty()


func test_returned_data_is_a_copy() -> void:
	var l := _link()
	l.threads()[0]["unread"] = 99
	l.messages(FakePhoneLink.ID_VOBLA, 8)[0]["text"] = "испорчено"
	assert_int(PhoneLogic.unread_total(l.threads())).is_equal(1)
	assert_str(l.messages(FakePhoneLink.ID_VOBLA, 8)[0]["text"]).is_not_equal("испорчено")


func test_scenario_delivers_messages_then_incoming_call_on_the_clock() -> void:
	var l := FakePhoneLink.new(T0, true)
	var got: Array = []
	l.message_received.connect(func(tid, msg): got.append([tid, msg["text"]]))
	l.advance(4.9)
	assert_array(got).is_empty()
	l.advance(0.2)   # 5.1 с: первое сообщение ВОБЛЫ
	assert_int(got.size()).is_equal(1)
	assert_str(got[0][0]).is_equal(FakePhoneLink.ID_VOBLA)
	assert_int(_thread_of(l, FakePhoneLink.ID_VOBLA)["unread"]).is_equal(1)
	l.advance(19.0)   # 24.1 с: звонок
	assert_int(got.size()).is_equal(3)
	assert_str(l.call_state()["phase"]).is_equal(PhoneLink.PHASE_INCOMING)
	assert_str(l.call_state()["peer"]).is_equal("ВОБЛА")


func test_scenario_repeats_when_looped_and_stops_when_not() -> void:
	var once := FakePhoneLink.new(T0, true, false)
	var looped := FakePhoneLink.new(T0, true, true)
	once.auto_reply = false
	looped.auto_reply = false
	var n_once := [0]
	var n_loop := [0]
	once.message_received.connect(func(_t, _m): n_once[0] += 1)
	looped.message_received.connect(func(_t, _m): n_loop[0] += 1)
	for t in 320:   # 320 с идём секундными шагами; звонки сценарий сам не принимает — они кончаются пропущенными
		once.advance(1.0)
		looped.advance(1.0)
	assert_int(n_once[0]).is_equal(5)    # пять сообщений за круг
	assert_int(n_loop[0]).is_equal(13)   # круги на 0 и 150 с целиком (5 + 5) и три сообщения третьего круга (на 305, 310 и 316 с)
	assert_int(looped.call_log().size()).is_greater(once.call_log().size())


func test_one_big_advance_runs_events_in_order_with_their_own_times() -> void:
	var l := FakePhoneLink.new(T0, true)
	l.auto_reply = false
	var times: Array = []
	l.message_received.connect(func(_tid, msg): times.append(msg["ts"]))
	l.advance(20.0)
	assert_int(times.size()).is_equal(3)
	assert_float(times[0]).is_equal_approx(T0 + 5.0, 0.001)
	assert_float(times[1]).is_equal_approx(T0 + 10.0, 0.001)
	assert_float(times[2]).is_equal_approx(T0 + 16.0, 0.001)
	assert_float(l.now()).is_equal_approx(T0 + 20.0, 0.001)


func test_mark_read_clears_unread_and_signals_once() -> void:
	var l := _link()
	var changes := [0]
	l.threads_changed.connect(func(): changes[0] += 1)
	l.mark_read(FakePhoneLink.ID_FACTION)
	assert_int(_thread_of(l, FakePhoneLink.ID_FACTION)["unread"]).is_equal(0)
	l.mark_read(FakePhoneLink.ID_FACTION)   # уже прочитан: сигнала нет
	assert_int(changes[0]).is_equal(1)


func test_send_text_adds_my_message_then_delivers_it() -> void:
	var l := _link()
	var before := l.messages(FakePhoneLink.ID_SHERSHEN, 20).size()
	l.send_text(FakePhoneLink.ID_SHERSHEN, "  Принято ")
	var msgs := l.messages(FakePhoneLink.ID_SHERSHEN, 20)
	assert_int(msgs.size()).is_equal(before + 1)
	assert_bool(msgs[-1]["mine"]).is_true()
	assert_str(msgs[-1]["text"]).is_equal("Принято")
	assert_str(msgs[-1]["status"]).is_equal(PhoneLink.STATUS_SENT)
	assert_str(_thread_of(l, FakePhoneLink.ID_SHERSHEN)["last_text"]).is_equal("Я: Принято")
	l.advance(FakePhoneLink.DELIVER_AFTER_S + 0.1)
	assert_str(l.messages(FakePhoneLink.ID_SHERSHEN, 1)[0]["status"]).is_equal(PhoneLink.STATUS_DELIVERED)


func test_send_text_to_offline_peer_fails() -> void:
	var l := _link()
	l.send_text(FakePhoneLink.ID_LIS, "ОК")
	l.advance(FakePhoneLink.FAIL_AFTER_S + 0.1)
	assert_str(l.messages(FakePhoneLink.ID_LIS, 1)[0]["status"]).is_equal(PhoneLink.STATUS_FAILED)


func test_send_text_ignores_empty_text_and_unknown_thread() -> void:
	var l := _link()
	var n := l.messages(FakePhoneLink.ID_VOBLA, 20).size()
	l.send_text(FakePhoneLink.ID_VOBLA, "   ")
	l.send_text("нет такого", "ОК")
	assert_int(l.messages(FakePhoneLink.ID_VOBLA, 20).size()).is_equal(n)


func test_peer_answers_a_quick_reply_and_calls_back_on_request() -> void:
	var l := FakePhoneLink.new(T0, false)
	var got: Array = []
	l.message_received.connect(func(tid, msg): got.append(msg["text"]))
	l.send_text(FakePhoneLink.ID_VOBLA, "Позвони")
	l.advance(FakePhoneLink.REPLY_AFTER_S + 0.1)
	assert_array(got).is_equal(["Сейчас наберу."])
	l.advance(FakePhoneLink.CALLBACK_AFTER_S)
	assert_str(l.call_state()["phase"]).is_equal(PhoneLink.PHASE_INCOMING)
	assert_str(l.call_state()["peer"]).is_equal("ВОБЛА")


func test_faction_message_keeps_author_in_preview() -> void:
	var l := _link()
	l.receive_message(FakePhoneLink.ID_FACTION, "ЛИС", "Идём")
	var t := _thread_of(l, FakePhoneLink.ID_FACTION)
	assert_str(t["last_text"]).is_equal("ЛИС: Идём")
	assert_str(l.messages(FakePhoneLink.ID_FACTION, 1)[0]["from"]).is_equal("ЛИС")


# ---------------------------------------------------------------- звонки

func test_incoming_call_accept_talk_hangup_writes_the_log() -> void:
	var l := _link()
	var phases: Array = []
	l.call_changed.connect(func(s): phases.append(s["phase"]))
	var log_before := l.call_log().size()
	l.incoming_call("ВОБЛА")
	var st := l.call_state()
	assert_str(st["phase"]).is_equal(PhoneLink.PHASE_INCOMING)
	assert_float(st["since_ts"]).is_equal_approx(T0, 0.001)
	l.advance(3.0)
	l.accept_call()
	st = l.call_state()
	assert_str(st["phase"]).is_equal(PhoneLink.PHASE_IN_CALL)
	assert_float(st["since_ts"]).is_equal_approx(T0 + 3.0, 0.001)   # таймер разговора идёт с момента «принять»
	l.advance(65.0)
	assert_float(PhoneLogic.call_elapsed(l.call_state(), l.now())).is_equal_approx(65.0, 0.01)
	l.hangup()
	assert_str(l.call_state()["phase"]).is_equal(PhoneLink.PHASE_IDLE)
	assert_array(phases).is_equal([PhoneLink.PHASE_INCOMING, PhoneLink.PHASE_IN_CALL, PhoneLink.PHASE_IDLE])
	var entries := l.call_log()
	assert_int(entries.size()).is_equal(log_before + 1)
	assert_str(entries[0]["peer"]).is_equal("ВОБЛА")
	assert_str(entries[0]["dir"]).is_equal(PhoneLink.DIR_IN)
	assert_float(entries[0]["duration_s"]).is_equal_approx(65.0, 0.01)


func test_decline_ends_incoming_call_without_duration() -> void:
	var l := _link()
	l.incoming_call("ШЕРШЕНЬ")
	l.decline_call()
	assert_str(l.call_state()["phase"]).is_equal(PhoneLink.PHASE_IDLE)
	var e: Dictionary = l.call_log()[0]
	assert_str(e["dir"]).is_equal(PhoneLink.DIR_IN)
	assert_float(e["duration_s"]).is_equal(0.0)


func test_unanswered_incoming_call_becomes_missed() -> void:
	var l := _link()
	l.incoming_call("ЛИС")
	l.advance(FakePhoneLink.RING_TIMEOUT_S - 1.0)
	assert_str(l.call_state()["phase"]).is_equal(PhoneLink.PHASE_INCOMING)
	l.advance(2.0)
	assert_str(l.call_state()["phase"]).is_equal(PhoneLink.PHASE_IDLE)
	assert_str(l.call_log()[0]["dir"]).is_equal(PhoneLink.DIR_MISSED)
	assert_str(l.call_log()[0]["peer"]).is_equal("ЛИС")


func test_busy_line_ignores_second_incoming_and_outgoing_calls() -> void:
	var l := _link()
	l.incoming_call("ВОБЛА")
	l.incoming_call("ШЕРШЕНЬ")
	l.start_call("ЛИС")
	assert_str(l.call_state()["peer"]).is_equal("ВОБЛА")
	assert_str(l.call_state()["phase"]).is_equal(PhoneLink.PHASE_INCOMING)


func test_outgoing_call_is_answered_and_hung_up() -> void:
	var l := _link()
	l.start_call("ВОБЛА")
	assert_str(l.call_state()["phase"]).is_equal(PhoneLink.PHASE_OUTGOING)
	l.advance(FakePhoneLink.ANSWER_AFTER_S["ВОБЛА"] + 0.1)
	assert_str(l.call_state()["phase"]).is_equal(PhoneLink.PHASE_IN_CALL)
	assert_float(l.call_state()["since_ts"]).is_equal_approx(T0 + FakePhoneLink.ANSWER_AFTER_S["ВОБЛА"], 0.001)   # разговор — с момента ответа
	l.advance(10.0)
	l.hangup()
	var e: Dictionary = l.call_log()[0]
	assert_str(e["dir"]).is_equal(PhoneLink.DIR_OUT)
	assert_float(e["duration_s"]).is_equal_approx(10.1, 0.01)


func test_cancelling_an_outgoing_call_is_logged_as_zero_length_and_stops_the_answer() -> void:
	var l := _link()
	l.start_call("ШЕРШЕНЬ")
	l.advance(1.0)
	l.hangup()
	assert_str(l.call_state()["phase"]).is_equal(PhoneLink.PHASE_IDLE)
	assert_float(l.call_log()[0]["duration_s"]).is_equal(0.0)
	l.advance(10.0)   # поздний «ответ» отменённого вызова не оживляет линию
	assert_str(l.call_state()["phase"]).is_equal(PhoneLink.PHASE_IDLE)


func test_call_to_offline_peer_drops_by_itself() -> void:
	var l := _link()
	l.start_call("ЛИС")
	l.advance(FakePhoneLink.UNREACHABLE_AFTER_S + 0.1)
	assert_str(l.call_state()["phase"]).is_equal(PhoneLink.PHASE_IDLE)
	assert_str(l.call_log()[0]["dir"]).is_equal(PhoneLink.DIR_OUT)


func test_mute_works_only_in_a_call_and_resets_for_the_next_one() -> void:
	var l := _link()
	l.set_muted(true)   # вне разговора ничего не значит
	assert_bool(l.call_state()["muted"]).is_false()
	l.incoming_call("ВОБЛА")
	l.accept_call()
	var seen: Array = []
	l.call_changed.connect(func(s): seen.append(s["muted"]))
	l.set_muted(true)
	l.set_muted(true)   # то же значение сигнала не даёт
	assert_array(seen).is_equal([true])
	l.hangup()
	l.incoming_call("ВОБЛА")
	l.accept_call()
	assert_bool(l.call_state()["muted"]).is_false()


func test_call_log_is_newest_first() -> void:
	var l := _link()
	l.incoming_call("ВОБЛА")
	l.decline_call()
	l.advance(30.0)
	l.incoming_call("ШЕРШЕНЬ")
	l.decline_call()
	var entries := l.call_log()
	assert_str(entries[0]["peer"]).is_equal("ШЕРШЕНЬ")
	assert_str(entries[1]["peer"]).is_equal("ВОБЛА")
	assert_bool(entries[0]["ts"] > entries[1]["ts"]).is_true()
