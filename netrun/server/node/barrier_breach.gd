class_name BarrierBreach
extends RefCounted
## Вскрытие барьера Soft ICE на сервере узла (docs/gamedesign/ice.md §5, levels.md §4.5). Два пути, оба — от клетки, соседней с блоком барьера:
##  • «charge» — мини-игра заряда в режиме движка for_barrier (цепочка 3/4/5 кодов по тиру узла, сетка 5×5, ловушек нет, буфер = цепочка + 2); тапы и отмена — те же bk_tap и
##    bk_cancel; успех — барьер открыт тихо (`open_barrier(.., "charge")`), неудача и время — барьер закрыт, последствий нет;
##  • «force» — силой: игрок удерживает курок FORCE_TICKS тактов подряд, не прыгая; отпустил (bk_cancel) или прыгнул — отмена; удержал — барьер открыт, trace +10, тревога +10.
## Попытка сессионная, как у ChargeBreach: мир идёт, телепорт, выброс, обрыв и переход её бросают без последствий. Одновременно у игрока одна мини-игра (взлом, заряд,
## расшифровка, барьер исключают друг друга). Начало мини-игры — ход (register_move), как у взлома.
##
## События игроку — те же, что у взлома, с mode = "barrier": bk (сетка или force: ticks), bk_tick (left или left_ticks), bk_end {outcome, barrier, opened, how, early?},
## bk_no {reason: not_ready | active | gone | open | far | no_barrier}.

const MODE := BreachRun.MODE_BARRIER
const FORCE_TICKS := 2
const HOW_CHARGE := "charge"
const HOW_FORCE := "force"


class Attempt:
	extends RefCounted
	var session := ""
	var barrier := ""
	var how := HOW_CHARGE
	var run: BreachRun
	var ticks_left := 0
	var sent_left := -1
	var ending := false


var node: GrayNode
var _by_session: Dictionary = {}   # сессия -> Attempt
var _rng := RandomNumberGenerator.new()
## Сколько попыток закончено и сколько из них открыли барьер — для тестов и журнала.
var finished_count := 0
var opened_count := 0


func _init(owner_node: GrayNode) -> void:
	node = owner_node
	_rng.randomize()


func has_attempt(session: String) -> bool:
	return _by_session.has(session)


func attempt_of(session: String) -> Attempt:
	return _by_session.get(session)


func clear_session(session: String) -> void:
	_by_session.erase(session)


## Проверка просьбы вскрыть барьер: {} — можно, иначе {reason}.
func check_start(session: String, barrier_id: String, how: String) -> Dictionary:
	var ds: DaemonSession = node._sessions.get(session)
	var avatar := node.net.get_avatar(session)
	if ds == null or avatar == null or node.net.node_of(session) != node.node_id or node._finishing.has(session):
		return {"reason": "not_ready"}
	if how != HOW_CHARGE and how != HOW_FORCE:
		return {"reason": "no_barrier"}
	if _by_session.has(session) or node.breach.has_attempt(session) or node.breach.is_opening(session) or node.charge.has_attempt(session) or node.decrypt.has_attempt(session):
		return {"reason": "active"}
	if not node.has_barrier(barrier_id):
		return {"reason": "no_barrier"}
	if not node.barrier_closed(barrier_id):
		return {"reason": "open"}
	if not node.barrier_adjacent(barrier_id, NodeGrid.cell_of(avatar.position)):
		return {"reason": "far"}
	return {}


## Клиент просит вскрыть барьер barrier_id способом how.
func request_start(session: String, barrier_id: String, how: String) -> void:
	var deny := check_start(session, barrier_id, how)
	if not deny.is_empty():
		_send_no(session, deny)
		return
	var att := Attempt.new()
	att.session = session
	att.barrier = barrier_id
	att.how = how
	if how == HOW_CHARGE:
		var run := BreachRun.for_barrier(node.tier(), _rng.randi())
		if run == null:
			_send_no(session, {"reason": "no_barrier"})
			return
		att.run = run
		var target: BreachDaemon = run.attempt.daemons[0]
		_by_session[session] = att
		node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {
			"kind": WorldMsg.EV_BK, "mode": MODE, "barrier": barrier_id, "how": how, "vault": "", "n": 0, "tier": run.tier,
			"grid": VaultBreach.public_grid(run.attempt.grid),
			"targets": [{"id": target.id, "name": target.display_name, "effect": target.effect, "cells": target.sequence.duplicate()}],
			"buffer": run.attempt.buffer_size, "sec": run.timer_sec,
		}))
		att.sent_left = run.seconds_left
	else:
		att.ticks_left = FORCE_TICKS
		_by_session[session] = att
		node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {
			"kind": WorldMsg.EV_BK, "mode": MODE, "barrier": barrier_id, "how": how, "ticks": FORCE_TICKS,
		}))
	node.event.emit({"kind": "barrier_start", "session": session, "barrier": barrier_id, "how": how})


## Тап клиента (только «charge»): принятый — ответ ok (и matched), отклонённый — ok=false.
func request_tap(session: String, cell: Array) -> void:
	var att: Attempt = _by_session.get(session)
	if att == null or att.ending or att.run == null or cell.size() != 2:
		return
	var c := Vector2i(int(cell[0]), int(cell[1]))
	var r := att.run.tap(c)
	var msg := {"kind": WorldMsg.EV_BK_TICK, "mode": MODE, "cell": [c.x, c.y], "ok": bool(r["ok"]), "left": att.run.seconds_left}
	if r["ok"]:
		msg["trap"] = false
		msg["matched"] = att.run.attempt.matched_daemon_ids()
	node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, msg))
	# Цепочка собрана — барьер готов, добивать буфер незачем.
	if r["ok"] and not r["finished"] and (msg["matched"] as Array).size() == att.run.attempt.daemons.size():
		att.run.resolve()
		r["finished"] = true
	if r["finished"]:
		_finish(att)


## «ОТМЕНА» мини-игры или отпущенный курок силового вскрытия.
func request_cancel(session: String) -> void:
	end_early(session, "cancel")


## Шаг времени: таймер мини-игры «charge», раз в секунду — `bk_tick` без клетки; время вышло — итог (барьер закрыт).
func tick(delta: float) -> void:
	if _by_session.is_empty():
		return
	for session in _by_session.keys():
		var att: Attempt = _by_session[session]
		if att.ending or att.run == null:
			continue
		att.run.advance(delta)
		if att.run.seconds_left != att.sent_left:
			att.sent_left = att.run.seconds_left
			node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {"kind": WorldMsg.EV_BK_TICK, "mode": MODE, "left": att.run.seconds_left}), false)
		if att.run.is_finished():
			_finish(att)


## Такт узла (после применения ходов): удержание силового вскрытия засчитывается, если игрок не прыгал (прыжок бросает попытку раньше).
func on_node_tick() -> void:
	for session in _by_session.keys():
		var att: Attempt = _by_session.get(session)
		if att == null or att.ending or att.how != HOW_FORCE:
			continue
		att.ticks_left -= 1
		node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {"kind": WorldMsg.EV_BK_TICK, "mode": MODE, "left_ticks": maxi(att.ticks_left, 0)}))
		if att.ticks_left <= 0:
			_finish(att, "", true)


## Попытку бросают (телепорт, выброс, обрыв, переход, «ОТМЕНА», отпущенный курок): барьер закрыт, последствий нет.
func end_early(session: String, reason: String) -> void:
	var att: Attempt = _by_session.get(session)
	if att != null and not att.ending:
		_finish(att, reason)


func _finish(att: Attempt, early: String = "", forced_done: bool = false) -> void:
	if att.ending:
		return
	att.ending = true
	var outcome := BreachRules.FAIL
	var seconds_left := 0
	if att.run != null:
		att.run.resolve()
		outcome = str(att.run.result_info()["outcome"])
		seconds_left = att.run.seconds_left
	elif forced_done:
		outcome = BreachRules.SUCCESS
	var opened := false
	if early == "" and outcome == BreachRules.SUCCESS and node._sessions.has(att.session):
		opened = node.open_barrier(att.barrier, att.how, att.session)
	_by_session.erase(att.session)
	finished_count += 1
	if opened:
		opened_count += 1
	var end := {"kind": WorldMsg.EV_BK_END, "mode": MODE, "barrier": att.barrier, "how": att.how, "outcome": outcome, "opened": opened, "left": seconds_left}
	if early != "":
		end["early"] = early
	node.net.send_to(att.session, WorldMsg.encode_fields(WorldMsg.EVENT, end))
	node.event.emit({"kind": "barrier_end", "session": att.session, "barrier": att.barrier, "how": att.how, "outcome": outcome, "opened": opened, "early": early})


func _send_no(session: String, deny: Dictionary) -> void:
	var msg := {"kind": WorldMsg.EV_BK_NO, "mode": MODE}
	msg.merge(deny)
	node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, msg))
