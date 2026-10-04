class_name FakePhoneLink
extends PhoneLink
## Фиктивная связь с телефоном: четыре диалога (один фракционный), сообщения и звонки приходят по сценарию на часах `advance()`,
## принять / отклонить / завершить / заглушить работают как в CallManager приложения (занятая линия новый вызов не принимает,
## вызов без ответа за RING_TIMEOUT_S становится пропущенным, каждый законченный звонок оставляет строку в журнале).
## Нужна, пока настоящей связи с телефоном нет: владелец оценивает на ней ощущения и читаемость деки в очках. Данные придуманы.
##
## Кто в сети: ВОБЛА и ШЕРШЕНЬ отвечают на сообщения и берут трубку; ЛИС «не в сети» — сообщение ей не доходит (статус failed),
## звонок обрывается (как UNREACHABLE в приложении). На заготовку «Позвони» собеседник перезванивает сам.

const RING_TIMEOUT_S := 45.0             ## как RING_TIMEOUT_MS в CallManager
const SCENARIO_PERIOD_S := 150.0         ## круг сценария при loop
const DELIVER_AFTER_S := 0.8
const FAIL_AFTER_S := 1.2
const REPLY_AFTER_S := 4.0
const CALLBACK_AFTER_S := 6.0
const UNREACHABLE_AFTER_S := 1.2
const OFFLINE_PEERS: Array[String] = ["ЛИС"]
## Через сколько секунд берёт трубку тот, кому позвонили.
const ANSWER_AFTER_S := {"ВОБЛА": 2.0, "ШЕРШЕНЬ": 3.0}
const DEFAULT_ANSWER_AFTER_S := 2.5

const ID_VOBLA := "dm:ВОБЛА"
const ID_SHERSHEN := "dm:ШЕРШЕНЬ"
const ID_LIS := "dm:ЛИС"
const ID_FACTION := "faction:ВОЛЬНЫЕ"
const FACTION_TITLE := "ВОЛЬНЫЕ"
## Кто отвечает во фракционном чате.
const FACTION_REPLIER := "ШЕРШЕНЬ"

## Что отвечает собеседник на заготовку; чего здесь нет — «Принято.».
const REPLIES := {
	"ОК": "Ок.",
	"Принято": "Отлично.",
	"Жди": "Жду.",
	"Я в Сети": "Вижу тебя.",
	"Позвони": "Сейчас наберу.",
	"Не могу говорить": "Понял, напишу.",
}

## Отвечать на сообщения самим (тесты выключают, чтобы не мешало счёту).
var auto_reply := true
## Секунды сценария; время связи — base_ts + clock.
var clock := 0.0
var base_ts := 0.0

var _threads: Array = []
var _msgs: Dictionary = {}
var _call: Dictionary = PhoneLink.idle_call()
var _call_id := 0
var _call_dir := PhoneLink.DIR_IN
var _call_started := 0.0
var _log: Array = []
var _timers: Array = []
var _next_id := 1


## start_ts — unix-время на начало (по умолчанию — настоящее), scenario — расписание сообщений и звонков, loop — повторять расписание
## каждые SCENARIO_PERIOD_S (на очках владелец может надеть их не сразу после запуска: события не должны кончиться раньше, чем он на них посмотрит).
func _init(start_ts: float = -1.0, scenario: bool = true, loop: bool = false) -> void:
	base_ts = start_ts if start_ts >= 0.0 else Time.get_unix_time_from_system()
	_seed_history()
	if scenario:
		_schedule_scenario(0.0, loop)


# ---------------------------------------------------------------- PhoneLink

func now() -> float:
	return base_ts + clock


func threads() -> Array:
	return _threads.duplicate(true)


func messages(thread_id: String, limit: int = PhoneLogic.MESSAGES_SHOWN) -> Array:
	var all: Array = _msgs.get(thread_id, [])
	if limit <= 0 or all.is_empty():
		return []
	return all.slice(maxi(all.size() - limit, 0)).duplicate(true)


func send_text(thread_id: String, text: String) -> void:
	var t := _thread(thread_id)
	var body := text.strip_edges()
	if t.is_empty() or body.is_empty():
		return
	var msg := _add_message(thread_id, true, body, "")
	t["last_text"] = "Я: " + body
	t["last_ts"] = msg["ts"]
	threads_changed.emit()
	var peer := _peer_of(t)
	var offline := peer in OFFLINE_PEERS
	var id: String = msg["id"]
	_after(FAIL_AFTER_S if offline else DELIVER_AFTER_S, func():
		_set_status(thread_id, id, PhoneLink.STATUS_FAILED if offline else PhoneLink.STATUS_DELIVERED))
	if offline:
		return
	if body == "Позвони":
		_after(CALLBACK_AFTER_S, func(): incoming_call(peer))
	if auto_reply:
		_after(REPLY_AFTER_S, func(): receive_message(thread_id, peer, REPLIES.get(body, "Принято.")))


func mark_read(thread_id: String) -> void:
	var t := _thread(thread_id)
	if not t.is_empty() and int(t["unread"]) > 0:
		t["unread"] = 0
		threads_changed.emit()


func call_state() -> Dictionary:
	return _call.duplicate()


func accept_call() -> void:
	if _call["phase"] == PhoneLink.PHASE_INCOMING:
		_connect()


func decline_call() -> void:
	if _call["phase"] == PhoneLink.PHASE_INCOMING:
		_finish_call(PhoneLink.DIR_IN)


func hangup() -> void:
	match _call["phase"]:
		PhoneLink.PHASE_OUTGOING:
			_finish_call(PhoneLink.DIR_OUT)   # отмена своего вызова
		PhoneLink.PHASE_IN_CALL:
			_finish_call(_call_dir)


func set_muted(muted: bool) -> void:
	if _call["phase"] == PhoneLink.PHASE_IN_CALL and bool(_call["muted"]) != muted:
		_call["muted"] = muted
		call_changed.emit(call_state())


func start_call(peer_id: String) -> void:
	if _call["phase"] != PhoneLink.PHASE_IDLE or peer_id.is_empty():
		return   # линия занята: как CallManager.startOutgoingCall при phase != IDLE
	_begin_call(PhoneLink.PHASE_OUTGOING, peer_id, PhoneLink.DIR_OUT)
	var id := _call_id
	if peer_id in OFFLINE_PEERS:
		_after(UNREACHABLE_AFTER_S, func():
			if _call_id == id and _call["phase"] == PhoneLink.PHASE_OUTGOING:
				_finish_call(PhoneLink.DIR_OUT))
	else:
		_after(float(ANSWER_AFTER_S.get(peer_id, DEFAULT_ANSWER_AFTER_S)), func():
			if _call_id == id and _call["phase"] == PhoneLink.PHASE_OUTGOING:
				_connect())


func call_log() -> Array:
	return _log.duplicate(true)


func advance(delta: float) -> void:
	var target := clock + maxf(delta, 0.0)
	while true:
		var idx := -1
		for i in _timers.size():
			if _timers[i]["at"] <= target and (idx < 0 or _timers[i]["at"] < _timers[idx]["at"]):
				idx = i
		if idx < 0:
			break
		var tm: Dictionary = _timers.pop_at(idx)
		clock = maxf(clock, tm["at"])
		(tm["fn"] as Callable).call()
	clock = target


# ---------------------------------------------------------------- события сценария (их же зовут тесты)

## Пришло сообщение от собеседника (в личный диалог или во фракционный).
func receive_message(thread_id: String, from: String, text: String) -> void:
	var t := _thread(thread_id)
	if t.is_empty():
		return
	var msg := _add_message(thread_id, false, text, from)
	t["last_text"] = ("%s: %s" % [from, text]) if t["kind"] == PhoneLink.KIND_FACTION else text
	t["last_ts"] = msg["ts"]
	t["unread"] = int(t["unread"]) + 1
	threads_changed.emit()
	message_received.emit(thread_id, msg.duplicate())


## Входящий звонок. Линия занята — молча игнорируется (как onOffer при phase != IDLE в CallManager).
func incoming_call(peer: String) -> void:
	if _call["phase"] != PhoneLink.PHASE_IDLE:
		return
	_begin_call(PhoneLink.PHASE_INCOMING, peer, PhoneLink.DIR_IN)
	var id := _call_id
	_after(RING_TIMEOUT_S, func():
		if _call_id == id and _call["phase"] == PhoneLink.PHASE_INCOMING:
			_finish_call(PhoneLink.DIR_MISSED))


# ---------------------------------------------------------------- внутреннее

func _begin_call(phase: String, peer: String, dir: String) -> void:
	_call_id += 1
	_call_dir = dir
	_call_started = now()
	_call = {"phase": phase, "peer": peer, "since_ts": _call_started, "muted": false}
	call_changed.emit(call_state())


func _connect() -> void:
	_call["phase"] = PhoneLink.PHASE_IN_CALL
	_call["since_ts"] = now()
	_call["muted"] = false
	call_changed.emit(call_state())


## Звонок закончился: строка в журнал, линия свободна. Длительность — только у состоявшегося разговора.
func _finish_call(dir: String) -> void:
	var talked := float(_call["since_ts"]) if _call["phase"] == PhoneLink.PHASE_IN_CALL else now()
	_log.push_front({"peer": _call["peer"], "dir": dir, "ts": _call_started, "duration_s": maxf(now() - talked, 0.0)})
	_call_id += 1   # отложенные ответы и таймеры этого вызова больше не действуют
	_call = PhoneLink.idle_call()
	call_changed.emit(call_state())


func _after(seconds: float, fn: Callable) -> void:
	_timers.append({"at": clock + seconds, "fn": fn})


func _thread(id: String) -> Dictionary:
	for t in _threads:
		if t["id"] == id:
			return t
	return {}


func _peer_of(t: Dictionary) -> String:
	return str(t["title"]) if t["kind"] == PhoneLink.KIND_DM else FACTION_REPLIER


func _add_message(thread_id: String, mine: bool, text: String, from: String) -> Dictionary:
	var msg := {"id": "m%d" % _next_id, "thread": thread_id, "mine": mine, "text": text, "ts": now(),
		"status": PhoneLink.STATUS_SENT if mine else PhoneLink.STATUS_DELIVERED, "from": from}
	_next_id += 1
	if not _msgs.has(thread_id):
		_msgs[thread_id] = []
	(_msgs[thread_id] as Array).append(msg)
	return msg


func _set_status(thread_id: String, msg_id: String, status: String) -> void:
	for m in _msgs.get(thread_id, []):
		if m["id"] == msg_id:
			m["status"] = status
			threads_changed.emit()
			return


## История до начала сценария: сообщения и журнал звонков за прошедшие часы.
func _seed_history() -> void:
	_new_thread(ID_VOBLA, PhoneLink.KIND_DM, "ВОБЛА")
	_new_thread(ID_FACTION, PhoneLink.KIND_FACTION, FACTION_TITLE)
	_new_thread(ID_SHERSHEN, PhoneLink.KIND_DM, "ШЕРШЕНЬ")
	_new_thread(ID_LIS, PhoneLink.KIND_DM, "ЛИС")
	_seed(ID_LIS, false, "ЛИС", "Не ходи в узел 07 без дешифратора.", -11000.0)
	_seed(ID_SHERSHEN, true, "", "Шард у меня.", -4000.0)
	_seed(ID_SHERSHEN, false, "ШЕРШЕНЬ", "Принято. Держи канал открытым.", -3900.0)
	_seed(ID_VOBLA, false, "ВОБЛА", "Привет. Ты уже на площадке?", -1800.0)
	_seed(ID_VOBLA, true, "", "Да, у терминала. Что нужно?", -1700.0)
	_seed(ID_VOBLA, false, "ВОБЛА", "Потом скажу. Не отключайся.", -1500.0)
	_seed(ID_FACTION, false, "ШЕРШЕНЬ", "Сбор у склада в 23:30.", -900.0)
	_seed(ID_FACTION, false, "ЛИС", "Буду.", -840.0)
	_thread(ID_FACTION)["unread"] = 1   # на старте у вкладки ЧАТ уже есть бейдж
	_log = [
		{"peer": "ШЕРШЕНЬ", "dir": PhoneLink.DIR_IN, "ts": base_ts - 3600.0, "duration_s": 125.0},
		{"peer": "ЛИС", "dir": PhoneLink.DIR_MISSED, "ts": base_ts - 7200.0, "duration_s": 0.0},
		{"peer": "ВОБЛА", "dir": PhoneLink.DIR_OUT, "ts": base_ts - 9000.0, "duration_s": 64.0},
		{"peer": "ШЕРШЕНЬ", "dir": PhoneLink.DIR_OUT, "ts": base_ts - 12000.0, "duration_s": 0.0},
	]


func _new_thread(id: String, kind: String, title: String) -> void:
	_threads.append({"id": id, "kind": kind, "title": title, "last_text": "", "last_ts": 0.0, "unread": 0})
	_msgs[id] = []


func _seed(thread_id: String, mine: bool, from: String, text: String, offset_s: float) -> void:
	var t := _thread(thread_id)
	var msg := {"id": "m%d" % _next_id, "thread": thread_id, "mine": mine, "text": text, "ts": base_ts + offset_s,
		"status": PhoneLink.STATUS_DELIVERED, "from": from}
	_next_id += 1
	(_msgs[thread_id] as Array).append(msg)
	t["last_text"] = ("Я: " + text) if mine else (("%s: %s" % [from, text]) if t["kind"] == PhoneLink.KIND_FACTION else text)
	t["last_ts"] = msg["ts"]


## Расписание (секунды от старта): три сообщения, звонок ВОБЛЫ, фракционная реплика, звонок ШЕРШЕНЯ, последнее сообщение. С loop
## после последнего события расписание начинается заново через SCENARIO_PERIOD_S от старта прошлого круга.
func _schedule_scenario(offset: float, loop: bool) -> void:
	_at(offset + 5.0, func(): receive_message(ID_VOBLA, "ВОБЛА", "Ты в Сети? Мне нужен ледокол на третий узел."))
	_at(offset + 10.0, func(): receive_message(ID_FACTION, "ШЕРШЕНЬ", "Охрана на втором этаже. Не светитесь."))
	_at(offset + 16.0, func(): receive_message(ID_VOBLA, "ВОБЛА", "Позвони, когда будешь свободен."))
	_at(offset + 24.0, func(): incoming_call("ВОБЛА"))
	_at(offset + 70.0, func(): receive_message(ID_FACTION, "ЛИС", "Кто видел Кассандра?"))
	_at(offset + 82.0, func(): incoming_call("ШЕРШЕНЬ"))
	_at(offset + 130.0, func(): receive_message(ID_VOBLA, "ВОБЛА", "Всё, я в канале. Выходи."))
	if loop:
		_at(offset + SCENARIO_PERIOD_S - 1.0, func(): _schedule_scenario(offset + SCENARIO_PERIOD_S, true))


func _at(seconds: float, fn: Callable) -> void:
	_timers.append({"at": seconds, "fn": fn})
