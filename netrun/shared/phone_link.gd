class_name PhoneLink
extends RefCounted
## Связь очков с телефоном игрока: всё, что нужно деке на левой руке для мессенджера и звонков.
##
## Схема владельца (4 октября 2026): очки — второй экран телефона. Телефон лежит в кармане включённым и остаётся хозяином личности,
## истории сообщений и WebRTC-звонка; очки показывают то, что он им отдаёт, и передают команды (ответить заготовкой, принять звонок).
## Голос звонка идёт через микрофон и динамики очков — это отдельный следующий этап; здесь только интерфейс. Деке всё равно, откуда
## данные: она работает с этим классом, а не с сетью. Сейчас его реализует `FakePhoneLink` (сценарий по таймеру), настоящая связь с
## телефоном — позже (тогда её место займёт другой потомок, дека не меняется).
##
## Формат данных (словари, поля стабильны):
##   диалог  {id, kind: "DM"|"FACTION", title, last_text, last_ts, unread: int}
##   сообщение {id, thread, mine: bool, text, ts, status: "sent"|"delivered"|"failed", from}
##       from — позывной автора (нужен во фракционном чате; в личном пуст), поле необязательное для читателя;
##   звонок  {phase: "idle"|"outgoing"|"incoming"|"in_call", peer, since_ts, muted}
##       phase как CallPhase в app (IDLE, OUTGOING_RINGING, INCOMING_RINGING, IN_CALL); peer — позывной собеседника;
##       since_ts — когда началась эта фаза (для «идёт вызов» — начало вызова, для «в разговоре» — начало разговора);
##   запись журнала звонков  {peer, dir: "in"|"out"|"missed", ts, duration_s}  (новые сверху).
## Время ts — секунды на часах самой связи (`now()`), для настоящей связи это unix-время.

## Пришло или изменилось что-то в диалогах и сообщениях (новое сообщение, прочитано, статус отправки).
signal threads_changed
## Пришло входящее сообщение (не своё).
signal message_received(thread_id: String, msg: Dictionary)
## Изменилась фаза звонка или его состояние (заглушён) или пополнился журнал звонков.
signal call_changed(state: Dictionary)
## Список контактов телефона пришёл или обновился (кадр contacts); фиктивная связь отдаёт готовый список и сигнала не шлёт.
signal contacts_changed

## Телефон принят (hello проверен, true) или пропал (false). Шлёт настоящая связь (RemotePhoneLink); фиктивная всегда на связи и сигнала не шлёт.
signal online_changed(online: bool)

const KIND_DM := "DM"
const KIND_FACTION := "FACTION"

const STATUS_SENT := "sent"
const STATUS_DELIVERED := "delivered"
const STATUS_FAILED := "failed"

const PHASE_IDLE := "idle"
const PHASE_OUTGOING := "outgoing"
const PHASE_INCOMING := "incoming"
const PHASE_IN_CALL := "in_call"

const DIR_IN := "in"
const DIR_OUT := "out"
const DIR_MISSED := "missed"


## Диалоги (порядок не гарантирован — сортирует показ, PhoneLogic.sort_threads).
func threads() -> Array:
	return []


## Последние `limit` сообщений диалога, старые первыми.
func messages(_thread_id: String, _limit: int = 8) -> Array:
	return []


## Отправить текст в диалог. В очках это только заготовки (PhoneLogic.QUICK_REPLIES): свободный текст — с телефона.
func send_text(_thread_id: String, _text: String) -> void:
	pass


## Диалог открыт и прочитан: непрочитанных не остаётся.
func mark_read(_thread_id: String) -> void:
	pass


func call_state() -> Dictionary:
	return PhoneLink.idle_call()


func accept_call() -> void:
	pass


func decline_call() -> void:
	pass


## Завершить разговор или отменить свой вызов, который ещё не приняли.
func hangup() -> void:
	pass


func set_muted(_muted: bool) -> void:
	pass


## Позвонить собеседнику (позывной). Идти может только один звонок: занятая линия вызов не начинает.
func start_call(_peer_id: String) -> void:
	pass


## Контакты телефона, которым можно отправить добычу (К5б): [{key, title}] — key обычный base64 X.509/SPKI телефона (как ключ игрока в Мосте),
## title — позывной. Телефон отправителя сюда не входит (на свой телефон Мост груз не отдаёт).
func contacts() -> Array:
	return []


## Журнал звонков, новые сверху.
func call_log() -> Array:
	return []


## Телефон на связи. Фиктивная связь всегда «на связи»; у настоящей (RemotePhoneLink) false, пока телефон не подключился или пропал: дека тогда пишет «ТЕЛЕФОН НЕ НА СВЯЗИ».
func is_online() -> bool:
	return true


## Текущее время связи, секунды (по нему дека считает таймер разговора).
func now() -> float:
	return Time.get_unix_time_from_system()


## Внешние часы: владелец вызывает каждый кадр. Настоящей связи они не нужны (события приходят сами), фиктивной — для сценария.
func advance(_delta: float) -> void:
	pass


static func idle_call() -> Dictionary:
	return {"phase": PHASE_IDLE, "peer": "", "since_ts": 0.0, "muted": false}
