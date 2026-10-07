extends GdUnitTestSuite
## Причина провала взлома на панели итога (BreachReason, п. 7 разбора П3): чистые строки по данным `bk_end` и счётчикам клиентской копии попытки.

const SUCCESS := BreachRules.SUCCESS
const PARTIAL := BreachRules.PARTIAL
const FAIL := BreachRules.FAIL


func test_успех_без_причины() -> void:
	assert_array(BreachReason.lines(SUCCESS, 2, true, 0, 5, [])).is_empty()


func test_замок_не_вскрыт_две_ловушки_из_двух_провал() -> void:
	assert_array(BreachReason.lines(FAIL, 2, false, 2, 2, [])).is_equal(["ЗАМОК: 2 ловушки из 2 нажатий — провал"])


func test_замок_не_вскрыт_без_ловушек() -> void:
	assert_array(BreachReason.lines(FAIL, 1, false, 0, 3, [])).is_equal(["ЗАМОК НЕ ВСКРЫТ"])


func test_ловушки_при_частичном_итоге_говорят_частично() -> void:
	assert_array(BreachReason.lines(PARTIAL, 2, false, 1, 4, [])).is_equal(["ЗАМОК: 1 ловушка из 4 нажатий — частично"])


func test_совпал_до_вскрытия_не_засчитан() -> void:
	assert_array(BreachReason.lines(PARTIAL, 1, true, 0, 4, ["d1"])).is_equal(["совпал до вскрытия — не засчитан"])
	assert_array(BreachReason.lines(PARTIAL, 1, true, 0, 4, ["d1", "d2"])).is_equal(["совпали до вскрытия — не засчитаны: 2"])


func test_замок_не_вскрыт_и_совпало_до_вскрытия_две_строки_замок_первый() -> void:
	var lines := BreachReason.lines(FAIL, 2, false, 0, 4, ["d1"])
	assert_array(lines).is_equal(["ЗАМОК НЕ ВСКРЫТ", "совпал до вскрытия — не засчитан"])


func test_замок_вскрыт_а_цепочек_нет() -> void:
	assert_array(BreachReason.lines(FAIL, 1, true, 0, 5, [])).is_equal(["ЗАМОК ВСКРЫТ, цепочек демонов не собрано"])


func test_без_замка_причин_про_замок_нет() -> void:
	assert_array(BreachReason.lines(FAIL, 0, false, 1, 3, [])).is_empty()   # без замка ловушки провал не объясняют


func test_склонение_ловушек() -> void:
	assert_str(BreachReason.plural_trap(1)).is_equal("ловушка")
	assert_str(BreachReason.plural_trap(2)).is_equal("ловушки")
	assert_str(BreachReason.plural_trap(5)).is_equal("ловушек")
	assert_str(BreachReason.plural_trap(11)).is_equal("ловушек")
	assert_str(BreachReason.plural_trap(21)).is_equal("ловушка")
	assert_str(BreachReason.plural_trap(0)).is_equal("ловушек")


func test_из_всех_нажатий_не_меньше_ловушек() -> void:
	assert_str(BreachReason.traps_text(3, 1)).is_equal("3 ловушки из 3 нажатий")   # нажатий меньше ловушек (откат) — не врём «3 из 1»
	assert_str(BreachReason.traps_text(1, 1)).is_equal("1 ловушка из 1 нажатия")
	assert_str(BreachReason.traps_text(2, 21)).is_equal("2 ловушки из 21 нажатия")
