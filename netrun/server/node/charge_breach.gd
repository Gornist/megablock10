class_name ChargeBreach
extends RefCounted
## Заряд защитного демона на сервере узла (К6, docs/netrun-deck-design.md §3.1, §3.3): короткая мини-игра на запястье в спокойный момент — режим движка for_charge
## (цель — цепочка самого демона, сетка и таймер по его тиру, буфер = длина + 2, ловушек нет). Совпала цепочка — демон заряжен: один заряд — один запуск
## (`use`), потом перезарядка из effects/<ЭФФЕКТ>.json. Попытка сессионная, как у VaultBreach, но без Моста, без номера попытки, без trace и без сигнала СБ:
## заряд — не взлом (design §9.1), последствий нет. Мир идёт, пока игрок собирает сетку; телепорт, выброс, обрыв, «ОТМЕНА» просто бросают попытку
## (заряда нет, повторить можно сразу: чисел для штрафа нет). Одновременно у игрока одна мини-игра: пока идёт взлом хранилища, заряд не начинается, и наоборот.
##
## События игроку — те же, что у взлома, с mode = "charge": bk (сетка), bk_tick, bk_end {outcome, daemon, charged}, bk_no {reason, left?}.

const MODE := BreachRun.MODE_CHARGE

## Одна попытка одного игрока.
class Attempt:
	extends RefCounted
	var session := ""
	var daemon := ""
	var run: BreachRun
	var sent_left := -1
	var ending := false


var node: GrayNode
var _by_session: Dictionary = {}   # сессия -> Attempt
var _rng := RandomNumberGenerator.new()
## Сколько попыток закончено и сколько из них дали заряд — для тестов и журнала.
var finished_count := 0
var charged_count := 0


func _init(owner_node: GrayNode) -> void:
	node = owner_node
	_rng.randomize()


func has_attempt(session: String) -> bool:
	return _by_session.has(session)


func attempt_of(session: String) -> Attempt:
	return _by_session.get(session)


func clear_session(session: String) -> void:
	_by_session.erase(session)


## Проверка просьбы «зарядить»: {} — можно, иначе {reason, left?}.
func check_start(session: String, daemon_id: String) -> Dictionary:
	var ds: DaemonSession = node._sessions.get(session)
	var avatar := node.net.get_avatar(session)
	if ds == null or avatar == null or node.net.node_of(session) != node.node_id or node._finishing.has(session):
		return {"reason": "not_ready"}
	if _by_session.has(session) or node.breach.has_attempt(session) or node.breach.is_opening(session):
		return {"reason": "active"}
	match node.daemons.charge_check(ds, daemon_id, node.now()):
		"":
			pass
		"cooldown":
			return {"reason": "cooldown", "left": ceili(ds.cooldown_left(daemon_id, node.now()))}
		"already_charged":
			return {"reason": "charged"}
		"not_chargeable", "effect_unsupported":
			return {"reason": "not_chargeable"}
		_:
			return {"reason": "bad_daemon"}
	if (ds.deck_meta.get(daemon_id, {}).get("cells", []) as Array).is_empty():
		return {"reason": "bad_daemon"}
	return {}


## Клиент просит зарядить демона daemon_id.
func request_start(session: String, daemon_id: String) -> void:
	var deny := check_start(session, daemon_id)
	if not deny.is_empty():
		_send_no(session, deny)
		return
	var ds: DaemonSession = node._sessions[session]
	var def := node.daemons.get_def(daemon_id)
	var cells: Array = ds.deck_meta[daemon_id]["cells"]
	var target := BreachDaemon.make(daemon_id, cells, def.effect, def.tier, node.daemons.display_name(daemon_id, daemon_id))
	var run := BreachRun.for_charge(target, _rng.randi())
	if run == null:
		_send_no(session, {"reason": "bad_daemon"})
		return
	var att := Attempt.new()
	att.session = session
	att.daemon = daemon_id
	att.run = run
	_by_session[session] = att
	node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {
		"kind": WorldMsg.EV_BK, "mode": MODE, "daemon": daemon_id, "vault": "", "n": 0, "tier": run.tier,
		"grid": VaultBreach.public_grid(run.attempt.grid),
		"targets": [{"id": target.id, "name": target.display_name, "effect": target.effect, "cells": target.sequence.duplicate()}],
		"buffer": run.attempt.buffer_size, "sec": run.timer_sec,
	}))
	att.sent_left = run.seconds_left
	node.event.emit({"kind": "charge_start", "session": session, "daemon": daemon_id, "tier": run.tier})


## Тап клиента: принятый — ответ ok (и matched), отклонённый — ok=false.
func request_tap(session: String, cell: Array) -> void:
	var att: Attempt = _by_session.get(session)
	if att == null or att.ending or cell.size() != 2:
		return
	var c := Vector2i(int(cell[0]), int(cell[1]))
	var r := att.run.tap(c)
	var msg := {"kind": WorldMsg.EV_BK_TICK, "mode": MODE, "cell": [c.x, c.y], "ok": bool(r["ok"]), "left": att.run.seconds_left}
	if r["ok"]:
		msg["trap"] = false
		msg["matched"] = att.run.attempt.matched_daemon_ids()
	node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, msg))
	# Цепочка собрана — заряд готов, добивать буфер незачем.
	if r["ok"] and not r["finished"] and (msg["matched"] as Array).size() == att.run.attempt.daemons.size():
		att.run.resolve()
		r["finished"] = true
	if r["finished"]:
		_finish(att)


func request_cancel(session: String) -> void:
	end_early(session, "cancel")


## Шаг времени: таймер попыток, раз в секунду — `bk_tick` без клетки; время вышло — итог (заряда нет).
func tick(delta: float) -> void:
	if _by_session.is_empty():
		return
	for session in _by_session.keys():
		var att: Attempt = _by_session[session]
		if att.ending:
			continue
		att.run.advance(delta)
		if att.run.seconds_left != att.sent_left:
			att.sent_left = att.run.seconds_left
			node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {"kind": WorldMsg.EV_BK_TICK, "mode": MODE, "left": att.run.seconds_left}), false)
		if att.run.is_finished():
			_finish(att)


## Попытку бросают (телепорт, выброс, обрыв, переход, «ОТМЕНА»): заряда нет, последствий нет.
func end_early(session: String, reason: String) -> void:
	var att: Attempt = _by_session.get(session)
	if att != null and not att.ending:
		_finish(att, reason)


func _finish(att: Attempt, early: String = "") -> void:
	if att.ending:
		return
	att.ending = true
	att.run.resolve()
	var session := att.session
	var info := att.run.result_info()
	var outcome := str(info["outcome"])
	var ds: DaemonSession = node._sessions.get(session)
	var charged := early == "" and outcome == BreachRules.SUCCESS and ds != null and node.daemons.charge_check(ds, att.daemon, node.now()) == ""
	if charged:
		ds.set_charged(att.daemon)
		charged_count += 1
	_by_session.erase(session)
	finished_count += 1
	var end := {"kind": WorldMsg.EV_BK_END, "mode": MODE, "daemon": att.daemon, "outcome": outcome, "charged": charged, "left": att.run.seconds_left}
	if early != "":
		end["early"] = early
	node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, end))
	node.event.emit({"kind": "charge_end", "session": session, "daemon": att.daemon, "outcome": outcome, "charged": charged, "early": early})


func _send_no(session: String, deny: Dictionary) -> void:
	var msg := {"kind": WorldMsg.EV_BK_NO, "mode": MODE}
	msg.merge(deny)
	node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, msg))
