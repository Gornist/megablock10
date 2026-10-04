extends GdUnitTestSuite
## Окно на «ушёл из игры» (AwayGuard): пауза, потеря фокуса, датчик на лбу, остановка сессии. Выход — только если игрок не вернулся
## за 15 секунд (решение владельца, 4 октября 2026). Время подаётся в миллисекундах прямо в вызовы.

const S := 1000


func test_the_window_is_fifteen_seconds() -> void:
	assert_float(AwayGuard.GRACE_SEC).is_equal(15.0)


func test_coming_back_inside_the_window_is_not_an_exit() -> void:
	var g := AwayGuard.new()
	g.begin("pause", 100 * S)
	assert_bool(g.end("pause", 114 * S + 900)).is_false()
	assert_bool(g.is_away()).is_false()


func test_coming_back_after_the_window_requests_the_exit_once() -> void:
	var g := AwayGuard.new()
	g.begin("pause", 0)
	assert_bool(g.end("pause", 15 * S)).is_true()          # ровно 15 с — уже выход
	g.begin("pause", 20 * S)
	assert_bool(g.end("pause", 60 * S)).is_false()         # второй раз тот же забег не просим
	assert_bool(g.due(100 * S)).is_false()


func test_due_fires_once_when_still_away_after_the_window() -> void:
	var g := AwayGuard.new()
	g.begin("focus", 0)
	assert_bool(g.due(14 * S + 999)).is_false()
	assert_bool(g.due(15 * S)).is_true()
	assert_bool(g.due(16 * S)).is_false()
	assert_bool(g.end("focus", 30 * S)).is_false()         # вернулся — выход уже был запрошен


func test_nothing_to_report_when_the_player_never_left() -> void:
	var g := AwayGuard.new()
	assert_bool(g.due(999 * S)).is_false()
	assert_bool(g.end("pause", 999 * S)).is_false()        # возвращение без ухода (focussed при запуске)
	assert_bool(g.is_away()).is_false()


func test_several_reasons_count_from_the_earliest_and_end_with_the_last() -> void:
	var g := AwayGuard.new()
	g.begin("focus", 0)                  # системное меню
	g.begin("pause", 5 * S)              # потом приложение ушло в паузу
	assert_bool(g.end("focus", 8 * S)).is_false()          # ещё в паузе
	assert_bool(g.is_away()).is_true()
	assert_bool(g.end("pause", 16 * S)).is_true()          # отсутствовал с 0-й секунды: 16 с
	assert_float(g.away_sec(16 * S)).is_equal(0.0)


func test_repeated_begin_of_the_same_reason_does_not_restart_the_clock() -> void:
	var g := AwayGuard.new()
	g.begin("focus", 0)
	g.begin("focus", 10 * S)
	assert_bool(g.due(15 * S)).is_true()


func test_a_short_away_then_a_new_one_starts_a_fresh_window() -> void:
	var g := AwayGuard.new()
	g.begin("pause", 0)
	assert_bool(g.end("pause", 10 * S)).is_false()
	g.begin("pause", 100 * S)
	assert_bool(g.due(110 * S)).is_false()
	assert_bool(g.due(115 * S)).is_true()


func test_reset_allows_the_next_run_to_request_the_exit_again() -> void:
	var g := AwayGuard.new()
	g.begin("pause", 0)
	assert_bool(g.end("pause", 20 * S)).is_true()
	g.reset()
	g.begin("pause", 100 * S)
	assert_bool(g.end("pause", 130 * S)).is_true()


func test_away_sec_counts_from_the_earliest_reason() -> void:
	var g := AwayGuard.new()
	assert_float(g.away_sec(5 * S)).is_equal(0.0)
	g.begin("presence", 2 * S)
	g.begin("focus", 4 * S)
	assert_float(g.away_sec(10 * S)).is_equal_approx(8.0, 0.001)
