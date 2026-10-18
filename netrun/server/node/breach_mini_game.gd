class_name BreachMiniGame
extends RefCounted
## Общий каркас серверных мини-игр узла (ChargeBreach, DecryptBreach, BarrierBreach, VaultBreach): сессионная попытка на BreachRun, `bk_tick` по тапам и по секундам,
## отмена и ранний уход, отказ `bk_no`. Подкласс задаёт `_mode()` (его константа MODE), свой `class Attempt extends BreachMiniGame.BaseAttempt` и `_finish`
## (итог у каждой мини-игры свой). Всё остальное — здесь, чтобы три копии не расходились; порядок и содержимое событий игроку не менялись.

## Общие поля одной попытки одного игрока; подкласс добавляет свои (демон, шард, барьер).
class BaseAttempt:
	extends RefCounted
	var session := ""
	var run: BreachRun
	var sent_left := -1
	var ending := false


var node: GrayNode
var _by_session: Dictionary = {}   # сессия -> Attempt
var _rng := RandomNumberGenerator.new()
## Сколько попыток закончено — для тестов и журнала.
var finished_count := 0


func _init(owner_node: GrayNode) -> void:
	node = owner_node
	_rng.randomize()


## Режим события (`mode` в bk_tick/bk_end/bk_no): константа MODE подкласса.
func _mode() -> String:
	push_error("BreachMiniGame._mode не переопределён")
	return ""


func has_attempt(session: String) -> bool:
	return _by_session.has(session)


func attempt_of(session: String) -> BaseAttempt:
	return _by_session.get(session)


func clear_session(session: String) -> void:
	_by_session.erase(session)


## Тап клиента: принятый — ответ ok (и matched), отклонённый — ok=false.
func request_tap(session: String, cell: Array) -> void:
	var att: BaseAttempt = _by_session.get(session)
	if att == null or att.ending or att.run == null or cell.size() != 2:
		return
	var c := Vector2i(int(cell[0]), int(cell[1]))
	var r := att.run.tap(c)
	var msg := {"kind": WorldMsg.EV_BK_TICK, "mode": _mode(), "cell": [c.x, c.y], "ok": bool(r["ok"]), "left": att.run.seconds_left}
	if r["ok"]:
		msg["trap"] = false
		msg["matched"] = att.run.attempt.matched_daemon_ids()
	node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, msg))
	# Цепочка собрана — цель достигнута, добивать буфер незачем.
	if r["ok"] and not r["finished"] and (msg["matched"] as Array).size() == att.run.attempt.daemons.size():
		att.run.resolve()
		r["finished"] = true
	if r["finished"]:
		_finish(att)


func request_cancel(session: String) -> void:
	end_early(session, "cancel")


## Шаг времени: таймер попыток, раз в секунду — `bk_tick` без клетки (ненадёжным каналом); время вышло — итог.
func tick(delta: float) -> void:
	if _by_session.is_empty():
		return
	for session in _by_session.keys():
		var att: BaseAttempt = _by_session[session]
		if att.ending or att.run == null:
			continue
		att.run.advance(delta)
		if att.run.seconds_left != att.sent_left:
			att.sent_left = att.run.seconds_left
			node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {"kind": WorldMsg.EV_BK_TICK, "mode": _mode(), "left": att.run.seconds_left}), false)
		if att.run.is_finished():
			_finish(att)


## Попытку бросают (телепорт, выброс, обрыв, переход, «ОТМЕНА»): последствий нет.
func end_early(session: String, reason: String) -> void:
	var att: BaseAttempt = _by_session.get(session)
	if att != null and not att.ending:
		_finish(att, reason)


## Итог попытки — у каждой мини-игры свой. Параметр без типа: подклассы принимают свой Attempt (и могут добавлять необязательные параметры).
func _finish(_att, _early: String = "") -> void:
	push_error("BreachMiniGame._finish не переопределён")


func _send_no(session: String, deny: Dictionary) -> void:
	var msg := {"kind": WorldMsg.EV_BK_NO, "mode": _mode()}
	msg.merge(deny)
	node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, msg))
