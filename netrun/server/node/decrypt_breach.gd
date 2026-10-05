class_name DecryptBreach
extends RefCounted
## Расшифровка зашифрованного шарда на месте (К7, docs/netrun-deck-design.md §3.1, контракт Моста — docs/netrun-bridge-protocol.md, 6.8): мини-игра на запястье
## в режиме движка for_decrypt (цепочка шифр-замка 3/4/5 по тиру шарда, сетка и таймер по тиру, буфер = цепочка + 2, ловушек нет — как на телефоне). Доступна, если
## среди рабочих демонов есть DECRYPT тира не ниже тира шарда (DeckDecrypt). Попытка сессионная, как у ChargeBreach: мир идёт, телепорт, выброс и «ОТМЕНА» её бросают
## без последствий. Одновременно у игрока одна мини-игра (взлом, заряд, расшифровка исключают друг друга).
##
## Успех мини-игры решает сервер мира; ценность (флаг «расшифрован» в payload) меняет Мост одной операцией `op.decrypt_item`: версия предмета берётся свежей,
## повтор безопасен (rid = decrypt:<сессия>:<предмет>:<ver>; ответ потеряли — предмет перечитывается и, если уже открыт, дело сделано). Пока Мост работает,
## исход забега ждёт (GrayNode.begin_inflight). Коллектору отдельной записи расшифровка в Сети не пишет (решение владельца).
##
## События игроку — те же, что у взлома, с mode = "decrypt": bk (сетка; targets — шифр-замок; item, title), bk_tick, bk_end {outcome, item, decrypted, early?, error?, body?},
## bk_no {reason: not_ready | active | no_bridge | not_shard | open | no_decrypter | gone}.

const MODE := BreachRun.MODE_DECRYPT
const NET_ATTEMPTS := 5
const VERSION_ATTEMPTS := 3
const RETRY_SEC := 0.6

class Attempt:
	extends RefCounted
	var session := ""
	var item := ""
	var title := ""
	var tier := 1
	var run: BreachRun
	var sent_left := -1
	var ending := false


var node: GrayNode
var _by_session: Dictionary = {}   # сессия -> Attempt (до конца обращения к Мосту)
var _rng := RandomNumberGenerator.new()
## Пауза между повторами при обрыве связи с Мостом, с (тест ставит поменьше).
var retry_sec := RETRY_SEC
## Сколько попыток закончено и сколько из них расшифровали шард — для тестов и журнала.
var finished_count := 0
var decrypted_count := 0


func _init(owner_node: GrayNode) -> void:
	node = owner_node
	_rng.randomize()


func has_attempt(session: String) -> bool:
	return _by_session.has(session)


func attempt_of(session: String) -> Attempt:
	return _by_session.get(session)


func clear_session(session: String) -> void:
	_by_session.erase(session)


## Рабочие демоны сессии как строки {id, effect, tier}: те же, что показывает дека (ds.deck).
func working_rows(ds: DaemonSession) -> Array:
	var rows: Array = []
	for id in ds.deck:
		var def := node.daemons.get_def(id)
		if def != null:
			rows.append({"id": id, "effect": def.effect, "tier": def.tier})
	return rows


## Проверка просьбы «расшифровать»: {} — можно, иначе {reason}.
func check_start(session: String, item: String) -> Dictionary:
	var ds: DaemonSession = node._sessions.get(session)
	var avatar := node.net.get_avatar(session)
	if ds == null or avatar == null or node.net.node_of(session) != node.node_id or node._finishing.has(session):
		return {"reason": "not_ready"}
	if _by_session.has(session) or node.charge.has_attempt(session) or node.breach.has_attempt(session) or node.breach.is_opening(session):
		return {"reason": "active"}
	if node.bridge == null or not node.bridge.is_ready():
		return {"reason": "no_bridge"}
	var row := {}
	for l in ds.loot_view:
		if str(l.get("id", "")) == item:
			row = l
	if row.is_empty():
		return {"reason": "gone"}
	if str(row.get("kind", "")) != "shard":
		return {"reason": "not_shard"}
	if not bool(row.get("enc", false)):
		return {"reason": "open"}
	if DeckDecrypt.best(working_rows(ds), int(row.get("tier", 1))).is_empty():
		return {"reason": "no_decrypter"}
	return {}


## Клиент просит расшифровать шард item.
func request_start(session: String, item: String) -> void:
	var deny := check_start(session, item)
	if not deny.is_empty():
		_send_no(session, deny)
		return
	var ds: DaemonSession = node._sessions[session]
	var row := {}
	for l in ds.loot_view:
		if str(l.get("id", "")) == item:
			row = l
	var tier := int(row.get("tier", 1))
	var run := BreachRun.for_decrypt(tier, _rng.randi())
	var att := Attempt.new()
	att.session = session
	att.item = item
	att.title = str(row.get("title", ""))
	att.tier = tier
	att.run = run
	_by_session[session] = att
	var lock := run.attempt.daemons[0] as BreachDaemon
	node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {
		"kind": WorldMsg.EV_BK, "mode": MODE, "item": item, "title": att.title, "vault": "", "n": 0, "tier": run.tier,
		"grid": VaultBreach.public_grid(run.attempt.grid),
		"targets": [{"id": lock.id, "name": lock.display_name, "effect": lock.effect, "cells": lock.sequence.duplicate()}],
		"buffer": run.attempt.buffer_size, "sec": run.timer_sec,
	}))
	att.sent_left = run.seconds_left
	node.event.emit({"kind": "decrypt_start", "session": session, "item": item, "tier": tier})


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
	# Цепочка замка собрана — добивать буфер незачем.
	if r["ok"] and not r["finished"] and (msg["matched"] as Array).size() == att.run.attempt.daemons.size():
		att.run.resolve()
		r["finished"] = true
	if r["finished"]:
		_finish(att)


func request_cancel(session: String) -> void:
	end_early(session, "cancel")


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


## Попытку бросают (телепорт, выброс, обрыв, переход, «ОТМЕНА»): шард остаётся зашифрованным, последствий нет. Уже ушедший в Мост запрос не отзывается.
func end_early(session: String, reason: String) -> void:
	var att: Attempt = _by_session.get(session)
	if att != null and not att.ending:
		_finish(att, reason)


## Итог мини-игры. Успех без досрочного ухода идёт в Мост (await внутри; вызывающий не ждёт).
func _finish(att: Attempt, early: String = "") -> void:
	if att.ending:
		return
	att.ending = true
	att.run.resolve()
	var outcome := str(att.run.result_info()["outcome"])
	var won := early == "" and outcome == BreachRules.SUCCESS
	var error := ""
	var body := ""
	if won:
		node.begin_inflight(att.session)
		var r := await _commit(att)
		node.end_inflight(att.session)
		won = bool(r.get("ok", false))
		error = str(r.get("error", ""))
		body = str(r.get("body", ""))
		if won and node._sessions.has(att.session):
			await node.refresh_deck(att.session)
	_by_session.erase(att.session)
	finished_count += 1
	if won:
		decrypted_count += 1
	var end := {"kind": WorldMsg.EV_BK_END, "mode": MODE, "item": att.item, "title": att.title, "outcome": outcome, "decrypted": won, "left": att.run.seconds_left}
	if early != "":
		end["early"] = early
	if error != "":
		end["error"] = error
	if body != "":
		end["body"] = body
	node.net.send_to(att.session, WorldMsg.encode_fields(WorldMsg.EVENT, end))
	node.event.emit({"kind": "decrypt_end", "session": att.session, "item": att.item, "outcome": outcome, "decrypted": won, "early": early, "error": error})


## Запрос в Мост с перечитыванием предмета: версия берётся свежей, version_conflict — новый круг, обрыв — повтор того же запроса (rid тот же), а если
## и после повторов ответа нет — предмет перечитывается: открыт — ответ потерялся после коммита. {ok, body?} либо {ok: false, error}.
func _commit(att: Attempt) -> Dictionary:
	var bridge := node.bridge
	for _round in VERSION_ATTEMPTS:
		var doc := await _read_item(att.item)
		if not doc.get("ok", false):
			return {"ok": false, "error": "unavailable"}
		var d: Dictionary = (doc["doc"] as Dictionary).get("data", {})
		if str(d.get("owner", "")) != "deck:" + att.session:
			return {"ok": false, "error": "gone"}
		if _is_open(d):
			return {"ok": true}   # прошлая попытка дошла до Моста, а ответ потерялся
		var ver := int((doc["doc"] as Dictionary).get("ver", 0))
		var resp: Dictionary = {}
		for _attempt in NET_ATTEMPTS:
			@warning_ignore("redundant_await")
			resp = await bridge.op_decrypt_item(att.session, att.item, ver)
			if not GrayNode.is_transient(resp) or not node.is_inside_tree():
				break
			await node.get_tree().create_timer(retry_sec).timeout
		if resp.get("ok", false):
			return {"ok": true, "body": str(resp.get("body", ""))}
		var code := BridgeApi.err_code(resp)
		if code == "version_conflict":
			continue
		if GrayNode.is_transient(resp):
			var again := await _read_item(att.item)
			if again.get("ok", false) and _is_open(((again["doc"] as Dictionary).get("data", {}) as Dictionary)):
				return {"ok": true}
			return {"ok": false, "error": "unavailable"}
		return {"ok": false, "error": error_for(code)}
	return {"ok": false, "error": "gone"}


static func _is_open(item_data: Dictionary) -> bool:
	var sh: Variant = item_data.get("shard")
	return sh is Dictionary and bool((sh as Dictionary).get("decrypted", false))


func _read_item(item: String) -> Dictionary:
	for _attempt in NET_ATTEMPTS:
		@warning_ignore("redundant_await")
		var r: Dictionary = await node.bridge.get_doc(BridgeApi.T_ITEM, item)
		if r.get("ok", false) or not GrayNode.is_transient(r) or not node.is_inside_tree():
			return r
		await node.get_tree().create_timer(retry_sec).timeout
	return BridgeApi.err("unavailable")


## Код ответа Моста -> причина для игрока.
static func error_for(code: String) -> String:
	match code:
		"wrong_owner", "not_found":
			return "gone"
		"no_decrypter":
			return "no_decrypter"
		"session_state":
			return "busy"
	return "refused"


func _send_no(session: String, deny: Dictionary) -> void:
	var msg := {"kind": WorldMsg.EV_BK_NO, "mode": MODE}
	msg.merge(deny)
	node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, msg))
