extends GdUnitTestSuite
## Чистая логика мессенджера и звонков деки (PhoneLogic): порядок диалогов, счётчики вкладок, подписи, время.


func _t(id: String, unread: int, ts: float) -> Dictionary:
	return {"id": id, "kind": "DM", "title": id, "last_text": "", "last_ts": ts, "unread": unread}


func test_threads_sort_unread_first_then_newest() -> void:
	var src := [_t("old_read", 0, 10.0), _t("new_read", 0, 50.0), _t("old_unread", 2, 20.0), _t("new_unread", 1, 40.0)]
	var ids: Array = PhoneLogic.sort_threads(src).map(func(t): return t["id"])
	assert_array(ids).is_equal(["new_unread", "old_unread", "new_read", "old_read"])
	assert_str(src[0]["id"]).is_equal("old_read")   # исходный порядок не тронут


func test_unread_total_sums_all_threads() -> void:
	assert_int(PhoneLogic.unread_total([_t("a", 2, 0.0), _t("b", 0, 0.0), _t("c", 3, 0.0)])).is_equal(5)
	assert_int(PhoneLogic.unread_total([])).is_equal(0)


func test_missed_unseen_is_missed_calls_minus_the_ones_already_seen() -> void:
	var entries := [
		{"peer": "a", "dir": "missed", "ts": 100.0, "duration_s": 0.0},
		{"peer": "b", "dir": "in", "ts": 200.0, "duration_s": 5.0},
		{"peer": "c", "dir": "missed", "ts": 300.0, "duration_s": 0.0},
	]
	assert_int(PhoneLogic.missed_count(entries)).is_equal(2)
	assert_int(PhoneLogic.missed_unseen(entries, 0)).is_equal(2)
	assert_int(PhoneLogic.missed_unseen(entries, 1)).is_equal(1)
	assert_int(PhoneLogic.missed_unseen(entries, 2)).is_equal(0)
	assert_int(PhoneLogic.missed_unseen(entries, 5)).is_equal(0)   # журнал усох — не уходим в минус
	assert_int(PhoneLogic.missed_count([])).is_equal(0)


func test_clock_text_uses_given_offset() -> void:
	# 1_700_000_000 = 2023-11-14 22:13:20 UTC
	assert_str(PhoneLogic.clock_text(1_700_000_000.0, 0)).is_equal("22:13")
	assert_str(PhoneLogic.clock_text(1_700_000_000.0, 180)).is_equal("01:13")
	var local := PhoneLogic.clock_text(1_700_000_000.0)   # часовой пояс системы
	assert_int(local.length()).is_equal(5)
	assert_str(local.substr(2, 1)).is_equal(":")


func test_duration_text() -> void:
	assert_str(PhoneLogic.duration_text(0.0)).is_equal("00:00")
	assert_str(PhoneLogic.duration_text(64.9)).is_equal("01:04")
	assert_str(PhoneLogic.duration_text(3723.0)).is_equal("1:02:03")
	assert_str(PhoneLogic.duration_text(-5.0)).is_equal("00:00")


func test_status_and_direction_texts_never_rely_on_colour() -> void:
	assert_str(PhoneLogic.status_text("failed")).is_equal("НЕ ДОСТАВЛЕНО")
	assert_str(PhoneLogic.status_text("delivered")).is_equal("ДОСТАВЛЕНО")
	assert_str(PhoneLogic.status_text("sent")).is_equal("ОТПРАВЛЕНО")
	assert_str(PhoneLogic.dir_text("missed")).is_equal("ПРОПУЩЕН")
	assert_str(PhoneLogic.dir_text("out")).is_equal("ИСХОДЯЩИЙ")
	assert_str(PhoneLogic.dir_text("in")).is_equal("ВХОДЯЩИЙ")


func test_call_headline_and_elapsed() -> void:
	var calling := {"phase": "outgoing", "peer": "x", "since_ts": 10.0, "muted": false}
	assert_str(PhoneLogic.call_headline(calling)).is_equal("ВЫЗЫВАЕМ…")
	assert_str(PhoneLogic.call_headline(PhoneLink.idle_call())).is_equal("")
	var talking := {"phase": "in_call", "peer": "x", "since_ts": 10.0, "muted": false}
	assert_float(PhoneLogic.call_elapsed(talking, 75.0)).is_equal(65.0)
	assert_float(PhoneLogic.call_elapsed(calling, 75.0)).is_equal(0.0)   # таймер только в разговоре


func test_badge_text_caps_at_nine() -> void:
	assert_str(PhoneLogic.badge_text(0)).is_equal("")
	assert_str(PhoneLogic.badge_text(3)).is_equal("3")
	assert_str(PhoneLogic.badge_text(25)).is_equal("9+")


func test_quick_replies_are_the_six_agreed_phrases() -> void:
	assert_array(PhoneLogic.QUICK_REPLIES).is_equal(["Да", "Нет", "Позже", "Перезвоню", "Привет", "Увидимся"])
	assert_array(PhoneLogic.QUICK_REPLY_IDS).is_equal(["yes", "no", "later", "callback", "hi", "cu"])
	assert_str(PhoneLogic.quick_reply_id("Позже")).is_equal("later")
	assert_str(PhoneLogic.quick_reply_id("что-то своё")).is_equal("")
