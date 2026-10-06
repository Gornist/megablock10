extends GdUnitTestSuite
## Часы тактов узла (TickClock): ходы, окно, свободные нетраннеры, пустой узел, «вдох». Время подаёт тест, без sleep.


func _clock() -> TickClock:
	var c := TickClock.new(5.0, 0.6)
	c.set_present(true, 0.0)
	return c


func test_ход_единственного_даёт_такт_не_раньше_минимального_интервала() -> void:
	var c := _clock()
	c.set_free(["a"])
	assert_bool(c.poll(0.1)).is_false()
	c.register_move("a")
	assert_bool(c.poll(0.3)).is_false()   # сходил, но ещё не прошло 0,6 с
	assert_bool(c.poll(0.6)).is_true()
	assert_int(c.tick_no).is_equal(1)
	assert_str(c.last_by).is_equal("moves")
	assert_int(c.last_moves).is_equal(1)
	assert_float(c.last_tick_at).is_equal(0.6)
	assert_bool(c.moved("a")).is_false()   # после такта ходы очищены
	assert_bool(c.poll(0.7)).is_false()


func test_не_сходил_такт_через_окно() -> void:
	var c := _clock()
	c.set_free(["a"])
	assert_bool(c.poll(4.9)).is_false()
	assert_bool(c.poll(5.0)).is_true()
	assert_str(c.last_by).is_equal("window")
	assert_int(c.last_moves).is_equal(0)
	assert_bool(c.poll(9.9)).is_false()
	assert_bool(c.poll(10.0)).is_true()
	assert_int(c.tick_no).is_equal(2)


func test_двое_ждём_обоих_но_не_дольше_окна() -> void:
	var c := _clock()
	c.set_free(["a", "b"])
	c.register_move("a")
	assert_bool(c.poll(2.0)).is_false()   # Бета ещё думает
	c.register_move("b")
	assert_bool(c.poll(2.0)).is_true()
	assert_str(c.last_by).is_equal("moves")
	assert_int(c.last_moves).is_equal(2)
	# Теперь Бета молчит: такт — по окну от прошлого такта.
	c.register_move("a")
	assert_bool(c.poll(6.9)).is_false()
	assert_bool(c.poll(7.0)).is_true()
	assert_str(c.last_by).is_equal("window")


func test_нетраннер_в_панели_такт_не_держит() -> void:
	var c := _clock()
	c.set_free(["a"])   # b — в панели взлома: не свободен
	c.register_move("a")
	assert_bool(c.poll(1.0)).is_true()
	# Все в панелях: ждать ходов не от кого — только окно.
	c.set_free([])
	c.register_move("a")
	assert_bool(c.poll(3.0)).is_false()
	assert_bool(c.poll(6.0)).is_true()
	assert_str(c.last_by).is_equal("window")


func test_нетраннеров_нет_тактов_нет() -> void:
	var c := TickClock.new(5.0, 0.6)
	assert_bool(c.poll(100.0)).is_false()
	assert_int(c.tick_no).is_equal(0)
	# Появился первый нетраннер: окно считается с этого момента.
	c.set_present(true, 100.0)
	c.set_free(["a"])
	assert_bool(c.poll(104.9)).is_false()
	assert_bool(c.poll(105.0)).is_true()
	# Узел опустел: тактов снова нет.
	c.set_present(false, 106.0)
	assert_bool(c.poll(200.0)).is_false()


func test_вдох_за_полсекунды_до_окна_но_не_перед_тактом_по_ходам() -> void:
	var c := _clock()
	c.set_free(["a"])
	assert_bool(c.inhale(4.0, 0.5)).is_false()
	assert_bool(c.inhale(4.5, 0.5)).is_true()
	assert_bool(c.inhale(4.99, 0.5)).is_true()
	c.register_move("a")   # такт по ходу наступит сразу: вдоха нет
	assert_bool(c.inhale(4.7, 0.5)).is_false()
	assert_bool(c.poll(5.0)).is_true()
	assert_bool(c.inhale(5.1, 0.5)).is_false()
