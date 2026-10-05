class_name PhoneLogic
extends RefCounted
## Чистая логика мессенджера и звонков деки: порядок диалогов, счётчики вкладок, подписи, время. Без узлов и сети —
## проверяется тестом (как HudLogic). Порядок и тексты — по docs/ux/ui-style-guide.md (раздел 6–7).

## Заготовки ответа: в очках отвечают только ими, без свободного текста и голосовых (docs/netrun.md: свободный текст — с телефона).
## Шесть фраз владельца (05.10.2026); id идут в кадр send_text настоящей связи (docs/netrun-phone-link.md), текст по id подставляет телефон.
const QUICK_REPLIES: Array[String] = ["Да", "Нет", "Позже", "Перезвоню", "Привет", "Увидимся"]
const QUICK_REPLY_IDS: Array[String] = ["yes", "no", "later", "callback", "hi", "cu"]


## id заготовки по тексту; пустая строка — такой заготовки нет (свободный текст очки не отправляют).
static func quick_reply_id(text: String) -> String:
	var i := QUICK_REPLIES.find(text)
	return QUICK_REPLY_IDS[i] if i >= 0 else ""
## Сколько последних сообщений диалога показывает дека.
const MESSAGES_SHOWN := 8


## Непрочитанные сверху, потом прочитанные; внутри группы — от новых к старым (стиль: «Сообщения»). Исходный массив не меняется.
static func sort_threads(threads: Array) -> Array:
	var out := threads.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ua := int(a.get("unread", 0)) > 0
		var ub := int(b.get("unread", 0)) > 0
		if ua != ub:
			return ua
		return float(a.get("last_ts", 0.0)) > float(b.get("last_ts", 0.0)))
	return out


static func unread_total(threads: Array) -> int:
	var n := 0
	for t in threads:
		n += int(t.get("unread", 0))
	return n


## Сколько пропущенных звонков в журнале. Бейдж вкладки «Звонки» = пропущенные минус те, что уже видели (число на момент последнего
## просмотра вкладки): по времени не считаем — пропущенный звонок записан временем начала вызова, а игрок мог видеть вызов и уйти.
static func missed_count(entries: Array) -> int:
	var n := 0
	for e in entries:
		if str(e.get("dir", "")) == PhoneLink.DIR_MISSED:
			n += 1
	return n


## Пропущенные, которых игрок ещё не видел: seen_missed — сколько их было при последнем просмотре. Журнал мог усохнуть — не меньше нуля.
static func missed_unseen(entries: Array, seen_missed: int) -> int:
	return maxi(missed_count(entries) - seen_missed, 0)


## «23:12»: время суток. tz_minutes — смещение от UTC в минутах (по умолчанию — часовой пояс системы).
static func clock_text(ts: float, tz_minutes: int = -99999) -> String:
	if tz_minutes == -99999:
		tz_minutes = int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(int(ts) + tz_minutes * 60)
	return "%02d:%02d" % [d["hour"], d["minute"]]


## Длительность разговора «01:42»; от часа — «1:02:03».
static func duration_text(seconds: float) -> String:
	var s := maxi(int(seconds), 0)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%02d:%02d" % [s / 60, s % 60]


## Подпись статуса своего сообщения (моношрифт, ЗАГЛАВНЫЕ): статус не держится на цвете.
static func status_text(status: String) -> String:
	match status:
		PhoneLink.STATUS_DELIVERED:
			return "ДОСТАВЛЕНО"
		PhoneLink.STATUS_FAILED:
			return "НЕ ДОСТАВЛЕНО"
	return "ОТПРАВЛЕНО"


## Метка направления в журнале звонков.
static func dir_text(dir: String) -> String:
	match dir:
		PhoneLink.DIR_MISSED:
			return "ПРОПУЩЕН"
		PhoneLink.DIR_OUT:
			return "ИСХОДЯЩИЙ"
	return "ВХОДЯЩИЙ"


## Фраза о состоянии вызова над кнопками: что сейчас происходит.
static func call_headline(state: Dictionary) -> String:
	match str(state.get("phase", PhoneLink.PHASE_IDLE)):
		PhoneLink.PHASE_INCOMING:
			return "ВХОДЯЩИЙ ВЫЗОВ"
		PhoneLink.PHASE_OUTGOING:
			return "ВЫЗЫВАЕМ…"
		PhoneLink.PHASE_IN_CALL:
			return "В ЭФИРЕ"
	return ""


## Сколько секунд идёт разговор по часам связи (0 — не в разговоре).
static func call_elapsed(state: Dictionary, now: float) -> float:
	if str(state.get("phase", "")) != PhoneLink.PHASE_IN_CALL:
		return 0.0
	return maxf(now - float(state.get("since_ts", now)), 0.0)


## Третья подпись вкладки: число для бейджа или пусто (0 — бейджа нет).
static func badge_text(count: int) -> String:
	if count <= 0:
		return ""
	return "9+" if count > 9 else str(count)
