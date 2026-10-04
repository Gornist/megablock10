class_name BridgeApi
extends TokenVerifier
## Интерфейс Моста для сервера мира (docs/netrun-bridge-protocol.md). Две реализации: BridgeClient (WebSocket к настоящему
## Мосту) и FakeBridge (в процессе, из JSON-фикстуры). Все методы-запросы — сопрограммы (`await`), ответ — словарь в форме
## протокола: {"ok": true, ...поля} или {"ok": false, "err": {"code", "msg", "doc"?}}.
## Номера запросов (`rid`) операций с ценностями детерминированные (раздел 6): после рестарта сервера мира повтор безопасен.

## Тип документа и состояние сессии (раздел 5).
const T_NODE := "node"
const T_SESSION := "session"
const T_ITEM := "item"
const T_TERMINAL := "terminal"
const T_RUNNER := "runner"

## Исходы забега для run.finish (раздел 6.5).
const OUTCOMES: PackedStringArray = ["clean", "emergency", "soft_ice", "black_ice", "aborted"]


static func ok(fields: Dictionary = {}) -> Dictionary:
	var r := {"ok": true}
	r.merge(fields)
	return r


static func err(code: String, msg: String = "", doc: Variant = null) -> Dictionary:
	var e := {"code": code, "msg": msg}
	if doc != null:
		e["doc"] = doc
	return {"ok": false, "err": e}


static func err_code(resp: Dictionary) -> String:
	if resp.get("ok", false):
		return ""
	return str((resp.get("err", {}) as Dictionary).get("code", "internal"))


static func take_rid(session: String, item: String) -> String:
	return "take:%s:%s" % [session, item]


static func leave_rid(session: String, item: String) -> String:
	return "leave:%s:%s" % [session, item]


static func finish_rid(session: String) -> String:
	return "finish:%s" % session


## Номер запроса итога взлома: n — номер попытки (session.world.breach_n), он же делает rid уникальным (docs/netrun-bridge-protocol.md, 6.6).
static func breach_rid(session: String, n: int) -> String:
	return "breach:%s:%d" % [session, n]


## Токен, который очки кладут в auth: JSON {"terminal","token"} или «терминал:токен». Возвращает {terminal, token} или {}.
## Разбор — в shared (NetConfig): клиент очков собирается без server/.
static func parse_terminal_token(raw: String) -> Dictionary:
	return NetConfig.parse_terminal_token(raw)


## Запускает соединение (для фейка — ничего не делает).
func start() -> void:
	pass


## Вызывается из _process владельца: опрос сокета, таймауты.
func poll() -> void:
	pass


func is_ready() -> bool:
	return false


## Синхронная проверка не поддерживается — Мост отвечает по сети. NetServer зовёт verify_async.
func verify(_token: String) -> String:
	return ""


## Сессия игрока по токену терминала: id открытой сессии (pending/active) или "" (токен не принят, сессии нет).
func verify_async(token: String) -> String:
	var tt := parse_terminal_token(token)
	if tt.is_empty():
		return ""
	var r: Dictionary = await terminal_auth(tt["terminal"], tt["token"])
	if not r.get("ok", false):
		return ""
	var s: Variant = r.get("session")
	if s is Dictionary:
		return str(s.get("id", ""))
	return ""


## Терминал по токену, в том числе без открытой сессии (P6): {"terminal", "session"}; токен не принят — {"terminal": "", "session": ""}.
func verify_terminal_async(token: String) -> Dictionary:
	var tt := parse_terminal_token(token)
	if tt.is_empty():
		return {"terminal": "", "session": ""}
	var r: Dictionary = await terminal_auth(tt["terminal"], tt["token"])
	if not r.get("ok", false):
		return {"terminal": "", "session": ""}
	var s: Variant = r.get("session")
	# node — узел из документа сессии: Мост сам подменяет его на учебный при первом входе нетраннера (tutorial_done: false).
	var node := ""
	if s is Dictionary and s.get("data") is Dictionary:
		node = str((s["data"] as Dictionary).get("node", ""))
	return {"terminal": tt["terminal"], "session": str(s.get("id", "")) if s is Dictionary else "", "node": node}


func terminal_auth(_terminal: String, _token: String) -> Dictionary:
	return err("internal", "не реализовано")


func session_confirm(_session: String, _terminal: String) -> Dictionary:
	return err("internal", "не реализовано")


func session_abort(_session: String, _reason: String) -> Dictionary:
	return err("internal", "не реализовано")


## battery, fps, link — необязательные (-1 = не передавать).
func terminal_beat(_terminal: String, _battery: int = -1, _fps: int = -1, _link: int = -1) -> Dictionary:
	return err("internal", "не реализовано")


func op_take_from_node(_session: String, _node: String, _item: String) -> Dictionary:
	return err("internal", "не реализовано")


func op_leave_in_node(_session: String, _node: String, _item: String) -> Dictionary:
	return err("internal", "не реализовано")


## moves: [{"item": id, "to": "phone"|"node"|"burned"}, ...].
func run_finish(_session: String, _outcome: String, _node: String, _disconnect: bool, _moves: Array) -> Dictionary:
	return err("internal", "не реализовано")


## Итог взлома хранилища (раздел 6.6). req: {n, tier (BASE|HARD|NIGHTMARE), selected [id демонов], matched [id], active [GHOST|TIMESKEW|BLACKOUT],
## vaults [id предметов в хранилищах узла, хранилище панели первым], open_s}. Ответ: {outcome, effects, eddies, loot_eddies, opened [{item, until}],
## exhausted, cooldown_until, alert}; отказы — cooldown, session_state, bad_request, not_found.
func run_breach(_session: String, _node: String, _req: Dictionary) -> Dictionary:
	return err("internal", "не реализовано")


## «Ждём мастера» (раздел 6a): критический шаг (kind: flatline, lockdown…) спрашивает, можно ли применять исход самому.
## Ответ {mode: "auto" | "wait" | "decided", decision: "approve" | "deny" | null, req}. wait — исход не применять, спросить позже.
func master_gate(_kind: String, _ref: String, _node: String, _summary: String) -> Dictionary:
	return err("internal", "не реализовано")


## Запись документа с проверкой версии (раздел 4): data заменяется целиком; ver 0 — создать. Ценности менять нельзя.
func put_doc(_type: String, _id: String, _ver: int, _data: Dictionary) -> Dictionary:
	return err("internal", "не реализовано")


## JSON отдаёт целые как float, а JSON.stringify пишет 300.0: Мост сравнил бы это с 300 как другое значение (ценность!).
## Приводит целые float к int во всём дереве — вызывать перед отправкой документа.
static func ints_of(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, roundf(v)) and absf(v) < 9.0e15:
		return int(v)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = ints_of(v[k])
		return out
	if v is Array:
		return v.map(func(x): return ints_of(x))
	return v


func get_doc(_type: String, _id: String) -> Dictionary:
	return err("internal", "не реализовано")


func list_docs(_type: String) -> Dictionary:
	return err("internal", "не реализовано")


## Подписка на типы документов; ответ — снимок {"seq", "docs"}, дальше сигнал doc_changed.
func subscribe(_types: Array) -> Dictionary:
	return err("internal", "не реализовано")


## Документ изменился: doc — как в протоколе, deleted — удалён.
signal doc_changed(doc: Dictionary, deleted: bool)
