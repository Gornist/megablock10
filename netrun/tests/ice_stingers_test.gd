extends GdUnitTestSuite
## Стингеры состояний Стража «как в MGS» (карточка Game w3-p4-sound-vault): переходы стадий, приоритет, ограничение частоты, громкости.


func _ice(st: int, lost := false, black := false) -> Dictionary:
	return {"st": st, "lost": lost, "black": black}


func test_переходы_стадий_дают_нужный_звук() -> void:
	assert_str(IceStingers.transition(0, 1, false, false)).is_equal("q")    # Патруль → Взгляд
	assert_str(IceStingers.transition(0, 2, false, false)).is_equal("q")    # Патруль → Проверка
	assert_str(IceStingers.transition(0, 3, false, false)).is_equal("alert")
	assert_str(IceStingers.transition(2, 3, false, false)).is_equal("alert")
	assert_str(IceStingers.transition(3, 0, false, false)).is_equal("lost")
	assert_str(IceStingers.transition(3, 2, false, false)).is_equal("lost")
	assert_str(IceStingers.transition(1, 1, false, false)).is_equal("")     # ничего не изменилось
	assert_str(IceStingers.transition(3, 3, false, false)).is_equal("")     # Поиск идёт — звука нет (только тревожный слой)
	assert_str(IceStingers.transition(1, 2, false, false)).is_equal("")     # Взгляд → Проверка: «?» уже звучал
	assert_str(IceStingers.transition(1, 0, true, false)).is_equal("lost")  # флаг «потерял» пришёл на этот такт
	assert_str(IceStingers.transition(1, 0, true, true)).is_equal("")       # он уже был — не повторять


func test_первый_снимок_без_звука_потом_ровно_один_стингер_на_переход() -> void:
	var s := IceStingers.new()
	assert_str(s.observe([_ice(0)], 1)).is_equal("")
	assert_str(s.observe([_ice(0)], 2)).is_equal("")
	assert_str(s.observe([_ice(1)], 3)).is_equal("q")
	assert_str(s.observe([_ice(1)], 4)).is_equal("")    # тот же «?» повторно не звучит
	assert_str(s.observe([_ice(3)], 5)).is_equal("alert")
	assert_str(s.observe([_ice(3)], 6)).is_equal("")
	assert_str(s.observe([_ice(0)], 7)).is_equal("lost")


func test_приоритет_при_нескольких_ice_в_одном_такте() -> void:
	var s := IceStingers.new()
	s.observe([_ice(0), _ice(3), _ice(0)], 1)
	# один ICE замечает («?»), второй теряет («…»), третий обнаруживает («!») — играет один, «!»
	assert_str(s.observe([_ice(1), _ice(0), _ice(3)], 2)).is_equal("alert")
	var t := IceStingers.new()
	t.observe([_ice(0), _ice(3)], 1)
	assert_str(t.observe([_ice(1), _ice(0)], 2)).is_equal("q")   # «?» > «…»
	assert_str(IceStingers.best(["lost", "q"])).is_equal("q")
	assert_str(IceStingers.best([])).is_equal("")


func test_один_и_тот_же_стингер_одного_ice_не_чаще_раза_в_cooldown_тактов() -> void:
	assert_int(IceStingers.COOLDOWN_TICKS).is_equal(2)
	var s := IceStingers.new()
	s.cooldown_ticks = 4   # строже обычного, чтобы мигание Патруль ↔ Взгляд упёрлось в лимит
	s.observe([_ice(0)], 1)
	assert_str(s.observe([_ice(1)], 2)).is_equal("q")
	s.observe([_ice(0)], 3)                               # вернулся в Патруль без «потерял»
	assert_str(s.observe([_ice(1)], 4)).is_equal("")      # прошло 2 такта < 4 — тот же «?» молчит
	s.observe([_ice(0)], 5)
	assert_str(s.observe([_ice(1)], 6)).is_equal("q")     # прошло 4 такта — можно
	# по умолчанию — раз в 2 такта: Патруль → Взгляд → Патруль → Взгляд укладывается ровно в лимит
	var t := IceStingers.new()
	t.observe([_ice(0)], 1)
	assert_str(t.observe([_ice(1)], 2)).is_equal("q")
	t.observe([_ice(0)], 3)
	assert_str(t.observe([_ice(1)], 4)).is_equal("q")


func test_black_ice_и_новый_ice_не_озвучиваются() -> void:
	var s := IceStingers.new()
	s.observe([_ice(0, false, true)], 1)
	assert_str(s.observe([_ice(3, false, true)], 2)).is_equal("")   # охота Black ICE — без стингера
	assert_str(s.observe([_ice(3, false, true), _ice(3)], 3)).is_equal("")   # новый ICE в списке: перехода нет


func test_тревожный_слой_пока_любой_ice_в_поиске() -> void:
	assert_bool(IceStingers.any_search([_ice(0), _ice(3)])).is_true()
	assert_bool(IceStingers.any_search([_ice(1), _ice(2)])).is_false()
	assert_bool(IceStingers.any_search([_ice(3, false, true)])).is_false()   # Black ICE не в счёт
	assert_bool(IceStingers.any_search([])).is_false()


func test_громкости_стингеров_относительно_пульса_и_тревожный_слой() -> void:
	var pulse_db := float(AudioSettings.DEFAULTS["tick"]["pulse_db"])
	var q := AudioParams.tick_params("q", 0.01)
	var al := AudioParams.tick_params("alert", 0.01)
	var lo := AudioParams.tick_params("lost", 0.01)
	assert_float(q["volume_db"]).is_equal_approx(pulse_db + 3.0, 0.001)
	assert_float(al["volume_db"]).is_equal_approx(pulse_db + 9.0, 0.001)   # самый громкий
	assert_float(lo["volume_db"]).is_equal_approx(pulse_db, 0.001)
	assert_float(al["volume_db"]).is_greater(q["volume_db"])
	assert_float(q["volume_db"]).is_greater(lo["volume_db"])
	# «?» — двухнотный восходящий; «…» — нисходящий; «!» — резкий тон, потом низкий удар
	assert_float(AudioParams.tick_params("q", 0.2)["hz"]).is_greater(AudioParams.tick_params("q", 0.05)["hz"])
	assert_float(AudioParams.tick_params("lost", 0.3)["hz"]).is_less(AudioParams.tick_params("lost", 0.01)["hz"])
	assert_float(AudioParams.tick_params("alert", 0.5)["hz"]).is_less(AudioParams.tick_params("alert", 0.02)["hz"])
	# звук конечен
	for k: String in ["q", "alert", "lost"]:
		assert_bool(AudioParams.tick_params(k, 5.0)["active"]).is_false()
	# тревожный слой: пульс выше тоном и громче на 2 дБ; щелчок тревогу не меняет
	var calm := AudioParams.tick_params("pulse", 0.01)
	var alarm := AudioParams.tick_params("pulse", 0.01, AudioSettings.DEFAULTS, true)
	assert_float(alarm["hz"]).is_greater(calm["hz"])
	assert_float(alarm["volume_db"]).is_equal_approx(float(calm["volume_db"]) + 2.0, 0.001)
	assert_float(AudioParams.tick_params("click", 0.01, AudioSettings.DEFAULTS, true)["hz"]).is_equal_approx(float(AudioParams.tick_params("click", 0.01)["hz"]), 0.001)


func test_tick_audio_играет_стингер_вместо_пульса_и_держит_тревогу() -> void:
	var a: TickAudio = auto_free(TickAudio.new())
	a.sting("alert")
	assert_str(a.kind).is_equal("alert")
	assert_int(int(a.stings["alert"])).is_equal(1)
	a.sting("q")
	assert_str(a.kind).is_equal("q")
	assert_bool(a.alarm).is_false()
