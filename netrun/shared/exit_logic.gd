class_name ExitLogic
extends RefCounted
## Чистая логика выхода (docs/netrun.md, «Забег»): удержание кнопки и причины экстренного отключения.
## Без узлов и сети — проверяется тестами gdUnit4.

const HOLD_SEC := 3.0
const REASON_MANUAL_HOLD := "manual_hold"
const REASON_HEADSET_OFF := "headset_off"
## Серверная причина: клиент прислать её не может, её ставит сам сервер по истечении окна возврата.
const REASON_CONNECTION_LOST := "connection_lost"

## Серверные причины узла (N7): чистый выход на площадке, выброс ICE, флэтлайн (trace 100).
const REASON_CLEAN := "clean"
const REASON_EJECTED := "ejected"
const REASON_FLATLINE := "flatline"

const CLIENT_REASONS := [REASON_MANUAL_HOLD, REASON_HEADSET_OFF]


## Новое состояние удержания: {held: сек, fired: bool}. fired — запрос уже отправлен (один раз за удержание).
static func hold_new() -> Dictionary:
	return {"held": 0.0, "fired": false}


## Шаг таймера. Отпустили кнопку — сброс; дошли до hold_sec — fired=true ровно один раз, пока кнопку не отпустят.
## Возвращает {held, fired, just_fired, progress}.
static func hold_step(state: Dictionary, pressed: bool, delta: float, hold_sec: float = HOLD_SEC) -> Dictionary:
	if not pressed:
		return {"held": 0.0, "fired": false, "just_fired": false, "progress": 0.0}
	var held := float(state.get("held", 0.0)) + maxf(delta, 0.0)
	var was_fired: bool = state.get("fired", false)
	var now_fired := was_fired or held >= hold_sec
	return {
		"held": held,
		"fired": now_fired,
		"just_fired": now_fired and not was_fired,
		"progress": clampf(held / hold_sec, 0.0, 1.0),
	}


## Принимает ли сервер такую причину от клиента (connection_lost с клиента — подделка бесплатного «обрыва»).
static func is_client_reason(reason: String) -> bool:
	return reason in CLIENT_REASONS


## Событие выхода. Деку сжигает только аварийный выход под охотой Black ICE; обрыв, которого не было видно
## никому, судится по тому же правилу: connection_lost под охотой тоже сжигает (иначе обрыв — бесплатное бегство).
static func build_event(session: String, reason: String, under_hunt: bool) -> Dictionary:
	return {"session": session, "reason": reason, "under_hunt": under_hunt, "deck_burned": under_hunt}


## Что про деку писать в журнале сервера. Сгорает дека только при аварийном выходе или обрыве под охотой; при флэтлайне она не горит,
## а остаётся в узле мёртвой (её может подобрать другой, docs/netrun.md, «Забег»), поэтому «сгорела» про флэтлайн было бы неверно.
static func deck_note(ev: Dictionary) -> String:
	if ev.get("reason", "") == REASON_FLATLINE:
		return "дека остаётся в узле мёртвой"
	return "дека сгорела" if ev.get("deck_burned", false) else ""
