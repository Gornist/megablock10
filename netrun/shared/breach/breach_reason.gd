class_name BreachReason
extends RefCounted
## Причина провала или частичного итога взлома одной строкой на панели (Взлом 2.0, п. 7 разбора П3): «ЗАМОК: 2 ловушки из 2 — провал», «ЗАМОК НЕ ВСКРЫТ»,
## «совпал до вскрытия — не засчитан». Чистая функция по данным итога `bk_end` (outcome, lock_opened, matched_before_lock) и счётчикам клиентской копии попытки
## (сколько ловушек сервер назвал в ответах `bk_tick`, сколько нажатий сделано): сервер ничего нового присылать не должен.


## Строки причины по важности (первая — крупно). Пусто у успеха. outcome — SUCCESS / PARTIAL / FAIL (BreachRules); lock_len — длина замка (0 — без замка);
## traps — ловушек в нажатиях; taps — всего нажатий; before_lock — id демонов, совпавших до вскрытия замка.
static func lines(outcome: String, lock_len: int, lock_opened: bool, traps: int, taps: int, before_lock: Array) -> Array[String]:
	var out: Array[String] = []
	if outcome == BreachRules.SUCCESS:
		return out
	var verdict := "частично" if outcome == BreachRules.PARTIAL else "провал"
	if lock_len > 0 and not lock_opened:
		if traps > 0:
			out.append("ЗАМОК: %s — %s" % [traps_text(traps, taps), verdict])
		else:
			out.append("ЗАМОК НЕ ВСКРЫТ")
	elif lock_len > 0 and outcome == BreachRules.FAIL:
		out.append("ЗАМОК ВСКРЫТ, цепочек демонов не собрано")
	if not before_lock.is_empty():
		if before_lock.size() == 1:
			out.append("совпал до вскрытия — не засчитан")
		else:
			out.append("совпали до вскрытия — не засчитаны: %d" % before_lock.size())
	return out


## «2 ловушки из 2» (нажатия, попавшие в ловушки, из всех нажатий).
static func traps_text(traps: int, taps: int) -> String:
	return "%d %s из %d" % [traps, plural_trap(traps), maxi(taps, traps)]


## Склонение «ловушка»: 1 ловушка, 2–4 ловушки, 0 и 5+ ловушек (11–14 — ловушек).
static func plural_trap(n: int) -> String:
	var m100 := n % 100
	var m10 := n % 10
	if m100 >= 11 and m100 <= 14:
		return "ловушек"
	if m10 == 1:
		return "ловушка"
	if m10 >= 2 and m10 <= 4:
		return "ловушки"
	return "ловушек"
