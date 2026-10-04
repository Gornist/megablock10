class_name VaultBreach
extends RefCounted
## Взлом хранилища на сервере узла (К3, docs/netrun-deck-design.md §3, §7): попытка живёт в сессии игрока, мир при этом не останавливается — ICE ходит,
## trace растёт, ловушка поднимает trace узла. Сетку строит и проверяет сервер (shared/breach, порт движка телефона): клиент просит «начать»,
## «клетка», «завершить» и только показывает; каждый тап подтверждается ответом `bk_tick`.
##
## Итог попытки (буфер полон, таймер, уход, выброс, телепорт, обрыв, «ЗАВЕРШИТЬ») уходит в Мост одной операцией run.breach (протокол 6.6): эдди, открытие
## хранилищ, остывание, сигнал СБ считает Мост. Номер попытки `n` растёт и пишется в session.world.breach_n ДО показа сетки — по нему rid переживает
## рестарт сервера мира. Рестарт посреди взлома — попытки не было. Пока операция в полёте, она числится в `_takes_inflight` узла: run.finish её дожидается.
## Без Моста (плоский стенд без фикстуры, учебный узел) итог считается здесь же: открывается хранилище, эдди и сигнала нет.

const BK_INTRO_EVENT := BreachRun.EVENT_INTRO
## Эффекты активных окон заряженных демонов, которые Мост учитывает в сигнале СБ (run.breach: active).
const ACTIVE_EFFECTS: Array = ["GHOST", "TIMESKEW", "BLACKOUT"]
const NUMBER_ATTEMPTS := 6
const NUMBER_RETRY_SEC := 0.3


## Одна попытка одного игрока.
class Attempt:
	extends RefCounted
	var session := ""
	var vault := ""
	var n := 0
	var tier := "BASE"
	var run: BreachRun
	var order: Array = []          # id выбранных демонов (порядок выбора)
	var names: Dictionary = {}     # id -> имя
	var sent_left := -1
	var ending := false
	var early := ""


var node: GrayNode
var _by_session: Dictionary = {}   # сессия -> Attempt
var _opening: Dictionary = {}      # сессия -> true, пока узнаём и пишем номер попытки в Мосте
var _n_local: Dictionary = {}      # сессия -> последний выданный номер (когда Моста нет и как нижняя граница)
var _rng := RandomNumberGenerator.new()
## Сколько попыток закончено / из них досрочно — для тестов и журнала.
var finished_count := 0


func _init(owner_node: GrayNode) -> void:
	node = owner_node
	_rng.randomize()


func has_attempt(session: String) -> bool:
	return _by_session.has(session)


## Идёт начало попытки (ждём номер у Моста): заряду в это время тоже нельзя начаться.
func is_opening(session: String) -> bool:
	return _opening.has(session)


func attempt_of(session: String) -> Attempt:
	return _by_session.get(session)


## Хранилище занято взломом другой сессии (С5: одна панель — один взломщик).
func is_busy(vault: String, session: String) -> bool:
	for s in _by_session:
		var a: Attempt = _by_session[s]
		if a.vault == vault and s != session:
			return true
	return false


func clear_session(session: String) -> void:
	_by_session.erase(session)
	_opening.erase(session)


# ---------------------------------------------------------------- вход

## Проверка просьбы «начать»: {} — можно, иначе {reason, left?}. recheck — после ожидания Моста (метка _opening уже не мешает).
func check_open(session: String, vault: String, ids: Array, recheck: bool = false) -> Dictionary:
	var ds: DaemonSession = node._sessions.get(session)
	var avatar := node.net.get_avatar(session)
	if ds == null or avatar == null or node.net.node_of(session) != node.node_id or node._finishing.has(session):
		return {"reason": "not_ready"}
	if _by_session.has(session) or (_opening.has(session) and not recheck):
		return {"reason": "active"}
	if node.charge.has_attempt(session) or node.decrypt.has_attempt(session):
		return {"reason": "charging"}
	if not node._slot_pos.has(vault):
		return {"reason": "not_ready"}
	if NodeLayout.flat_distance(avatar.position, node.net.object_position(vault)) > NodeLayout.BREACH_REACH:
		return {"reason": "far"}
	if node.net.holder_of(vault) != "":
		return {"reason": "empty", "left": node.refill_left(vault)}
	if node._vault_open.get(vault) == session or (node.vault_state(vault, session) == GrayNode.VAULT_OPEN and not node.vault_requires_open()):
		return {"reason": "open"}
	if is_busy(vault, session):
		return {"reason": "busy"}
	if not node.is_tutorial():
		var left := cooldown_left(ds)
		if left > 0.0:
			return {"reason": "cooldown", "left": ceili(left)}
	if ids.is_empty() or ids.size() != _unique(ids).size():
		return {"reason": "bad_daemons"}
	var total := 0
	for id in ids:
		var meta: Dictionary = ds.deck_meta.get(id, {})
		var cells: Array = meta.get("cells", [])
		if not ds.deck.has(id) or node.daemons.get_def(id) == null or cells.is_empty():
			return {"reason": "bad_daemons"}
		total += cells.size()
	if total > ds.ram:
		return {"reason": "bad_daemons"}
	return {}


## Секунд до конца остывания узла для игрока (0 — не остывает).
func cooldown_left(ds: DaemonSession) -> float:
	var until := int(ds.breach_cooldown.get(node.node_id, 0))
	return maxf((until - Time.get_unix_time_from_system() * 1000.0) / 1000.0, 0.0)


## Клиент просит начать взлом хранилища vault выбранными демонами ids.
func request_open(session: String, vault: String, ids: Array) -> void:
	var deny := check_open(session, vault, ids)
	if not deny.is_empty():
		_send_no(session, deny)
		return
	_opening[session] = true
	var n := await _next_number(session)
	if n < 0:
		_opening.erase(session)
		_send_no(session, {"reason": "bridge"})
		return
	deny = check_open(session, vault, ids, true)   # пока ждали Мост, игрок мог уйти или хранилище — стать занятым
	_opening.erase(session)
	if not deny.is_empty():
		_send_no(session, deny)
		return
	var ds: DaemonSession = node._sessions[session]
	var daemons: Array = []
	var att := Attempt.new()
	for id in ids:
		var def := node.daemons.get_def(id)
		var meta: Dictionary = ds.deck_meta[id]
		var d := BreachDaemon.make(id, meta["cells"], def.effect, def.tier, node.daemons.display_name(id, id))
		daemons.append(d)
		att.names[id] = d.display_name
	att.session = session
	att.vault = vault
	att.n = n
	att.tier = node.breach_tier()
	att.order = ids.duplicate()
	att.run = BreachRun.for_storage(att.tier, daemons, ds.ram, _rng.randi())
	if att.run == null:
		_send_no(session, {"reason": "bad_daemons"})
		return
	_by_session[session] = att
	var targets: Array = []
	for d in daemons:
		targets.append({"id": d.id, "name": d.display_name, "effect": d.effect, "cells": d.sequence.duplicate()})
	node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {
		"kind": WorldMsg.EV_BK, "mode": att.run.mode, "vault": vault, "n": n, "tier": att.tier, "grid": public_grid(att.run.attempt.grid),
		"targets": targets, "buffer": ds.ram, "sec": att.run.timer_sec, "ice": att.run.ice_line(BK_INTRO_EVENT),
	}))
	att.sent_left = att.run.seconds_left
	node.event.emit({"kind": "breach_start", "session": session, "vault": vault, "n": n, "tier": att.tier})
	node._push_shards()   # остальным: хранилище занято


## Сетка для клиента: размер, коды и мёртвые клетки. Порченые коды (ловушки среди обычных) НЕ выдаём — это и есть их смысл; путь решения тоже.
static func public_grid(grid: BreachGrid) -> Dictionary:
	var traps: Array = []
	for c in grid.trap_cells:
		if grid.is_dead(c):
			traps.append([c.x, c.y])
	traps.sort()
	var rows: Array = []
	for r in grid.cells:
		rows.append((r as Array).duplicate())
	return {"size": grid.size, "cells": rows, "traps": traps, "dead_marker": grid.dead_marker}


## Следующий номер попытки: max(world.breach_n, breach.n) + 1; запись world.breach_n в Мост — до показа сетки. -1 — не вышло (попытку не начинаем).
func _next_number(session: String) -> int:
	var local := int(_n_local.get(session, 0))
	if node.bridge == null or node.is_tutorial():
		_n_local[session] = local + 1
		return local + 1
	for attempt in NUMBER_ATTEMPTS:
		@warning_ignore("redundant_await")
		var g: Dictionary = await node.bridge.get_doc(BridgeApi.T_SESSION, session)
		var code := BridgeApi.err_code(g)
		if g.get("ok", false):
			var cur: Dictionary = g["doc"]
			var data: Dictionary = (cur.get("data", {}) as Dictionary).duplicate(true)
			var w: Dictionary = (data.get("world", {}) as Dictionary).duplicate(true) if data.get("world") is Dictionary else {}
			var b: Dictionary = data.get("breach", {}) if data.get("breach") is Dictionary else {}
			var n := maxi(maxi(int(w.get("breach_n", 0)), int(b.get("n", 0))), local) + 1
			w["breach_n"] = n
			data["world"] = w
			@warning_ignore("redundant_await")
			var r: Dictionary = await node.bridge.put_doc(BridgeApi.T_SESSION, session, int(cur["ver"]), data)
			if r.get("ok", false):
				_n_local[session] = n
				return n
			code = BridgeApi.err_code(r)
		if code != "version_conflict" and not GrayNode.is_transient({"ok": false, "err": {"code": code}}):
			return -1
		if not node.is_inside_tree():
			return -1
		if code != "version_conflict":
			await node.get_tree().create_timer(NUMBER_RETRY_SEC).timeout
	return -1


# ---------------------------------------------------------------- ход

## Тап клиента. Принятый — ответ ok (и trap/matched/ice), отклонённый — ok=false: клиент откатит подсветку.
func request_tap(session: String, cell: Array) -> void:
	var att: Attempt = _by_session.get(session)
	if att == null or att.ending or cell.size() != 2:
		return
	var c := Vector2i(int(cell[0]), int(cell[1]))
	var r := att.run.tap(c)
	var msg := {"kind": WorldMsg.EV_BK_TICK, "cell": [c.x, c.y], "ok": bool(r["ok"]), "left": att.run.seconds_left}
	if r["ok"]:
		msg["trap"] = bool(r["hit_trap"])
		msg["matched"] = att.run.attempt.matched_daemon_ids()
		var line := att.run.ice_line(str(r["ice_event"])) if str(r["ice_event"]) != "" else ""
		if line != "":
			msg["ice"] = line
		if r["hit_trap"]:
			_trap_hit(session, att)
	node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, msg))
	# Совпали все цели — дальше тапать незачем: совпадения не пропадают, исход тот же SUCCESS. Не заставляем игрока добивать буфер.
	if r["ok"] and not r["finished"] and (msg["matched"] as Array).size() == att.run.attempt.daemons.size():
		att.run.resolve()
		r["finished"] = true
	if r["finished"]:
		_finish(att)


## Ловушка: trace игрока растёт на trap_trace[тир узла]; сигнал для журнала и звука.
func _trap_hit(session: String, att: Attempt) -> void:
	var ds: DaemonSession = node._sessions.get(session)
	var amount := float((node.settings["trap_trace"] as Dictionary).get(att.tier, 0.0))
	if ds != null:
		ds.trace.add_amount(amount, node.now())
	node.event.emit({"kind": "breach_trap", "session": session, "vault": att.vault, "trace": amount})


func request_cancel(session: String) -> void:
	end_early(session, "cancel")


## Шаг времени: таймер попыток, реплики по времени, раз в секунду — `bk_tick` без клетки; время вышло — итог.
func tick(delta: float) -> void:
	if _by_session.is_empty():
		return
	for session in _by_session.keys():
		var att: Attempt = _by_session[session]
		if att.ending:
			continue
		var lines: Array[String] = []
		for ev in att.run.advance(delta):
			var line := att.run.ice_line(ev)
			if line != "":
				lines.append(line)
		if att.run.seconds_left != att.sent_left or not lines.is_empty():
			att.sent_left = att.run.seconds_left
			var msg := {"kind": WorldMsg.EV_BK_TICK, "left": att.run.seconds_left}
			if not lines.is_empty():
				msg["ice"] = lines[-1]
			node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, msg), false)
		if att.run.is_finished():
			_finish(att)


## Досрочный итог по собранному (телепорт, выброс, обрыв, «ЗАВЕРШИТЬ», уход в тоннель): подсмотреть сетку и уйти без последствий нельзя.
func end_early(session: String, reason: String) -> void:
	var att: Attempt = _by_session.get(session)
	if att != null and not att.ending:
		_finish(att, reason)


# ---------------------------------------------------------------- итог

func _finish(att: Attempt, early: String = "") -> void:
	if att.ending:
		return
	att.ending = true
	att.early = early
	att.run.resolve()
	var session := att.session
	var info := att.run.result_info()
	var outcome := str(info["outcome"])
	var matched: Array = (info["matched"] as Array).duplicate()
	var ds: DaemonSession = node._sessions.get(session)
	var active: Array = []
	if ds != null:
		for e in ds.active_effects(node.now()):
			if e in ACTIVE_EFFECTS:
				active.append(e)
	var req := {
		"n": att.n, "tier": att.tier, "selected": att.order.duplicate(), "matched": matched, "active": active,
		"vaults": _vault_items(att.vault), "open_s": clampi(roundi(float(node.settings.get("vault_open_sec", 60.0))), 1, 600),
	}
	# Пока операция в полёте, run.finish игрока её дожидается (общий счётчик узла).
	node._takes_inflight[session] = int(node._takes_inflight.get(session, 0)) + 1
	var resp: Dictionary
	if node.bridge == null or node.is_tutorial():
		resp = _local_result(att, outcome, matched)
	else:
		for attempt in GrayNode.FINISH_ATTEMPTS:
			@warning_ignore("redundant_await")
			resp = await node.bridge.run_breach(session, node.node_id, req)
			if not GrayNode.is_transient(resp) or not node.is_inside_tree():
				break
			await node.get_tree().create_timer(GrayNode.FINISH_RETRY_SEC).timeout
	node._takes_inflight[session] = maxi(int(node._takes_inflight.get(session, 0)) - 1, 0)
	_by_session.erase(session)
	finished_count += 1
	_apply_result(att, outcome, matched, resp)


## Предметы, лежащие сейчас в хранилищах узла: хранилище панели первым (протокол 6.6, `vaults`).
func _vault_items(first_slot: String) -> Array:
	var out: Array = []
	var first: String = node._shard_items.get(first_slot, "")
	if first != "":
		out.append(first)
	for slot in node._slot_pos:
		var item: String = node._shard_items.get(slot, "")
		if item != "" and item not in out and node.net.holder_of(slot) == "":
			out.append(item)
	return out


## Итог без Моста: совпавший EXTRACT_* открывает хранилище — сначала панели, потом остальные лежащие; эдди, остывания и сигнала нет.
func _local_result(att: Attempt, outcome: String, matched: Array) -> Dictionary:
	var ds: DaemonSession = node._sessions.get(att.session)
	var slots: Array = []
	if outcome != BreachRules.FAIL and ds != null:
		var free: Array = [att.vault]
		for slot in node._slot_pos:
			if slot != att.vault:
				free.append(slot)
		for id in matched:
			var def := node.daemons.get_def(id)
			if def == null or def.effect not in ["EXTRACT_SHARD", "EXTRACT_DAEMON"]:
				continue
			while not free.is_empty():
				var slot: String = free.pop_front()
				if node.net.holder_of(slot) == "" and not slots.has(slot):
					slots.append(slot)
					break
	return {"ok": true, "local": true, "outcome": outcome, "eddies": 0, "opened_slots": slots, "exhausted": false, "cooldown_until": 0, "alert": null}


func _apply_result(att: Attempt, outcome: String, matched: Array, resp: Dictionary) -> void:
	var session := att.session
	var ds: DaemonSession = node._sessions.get(session)
	var opened: Array = []
	var end := {"kind": WorldMsg.EV_BK_END, "outcome": outcome, "matched": matched, "n": att.n, "vault": att.vault, "eddies": 0, "alert": ""}
	if att.early != "":
		end["early"] = att.early
	if resp.get("ok", false):
		end["eddies"] = int(resp.get("eddies", 0))
		end["exhausted"] = bool(resp.get("exhausted", false))
		if resp.has("opened_slots"):
			opened = resp["opened_slots"]
		else:
			var open_s := float(node.settings.get("vault_open_sec", 60.0))
			for o in resp.get("opened", []):
				var slot := node.slot_of_item(str(o.get("item", "")))
				if slot != "":
					opened.append(slot)
					# Срок — по часам Моста (until, мс Unix): сервер мира считает от сейчас, расхождение часов не страшно.
					var left := maxf((float(o.get("until", 0)) - Time.get_unix_time_from_system() * 1000.0) / 1000.0, 0.0)
					node.open_vault(slot, session, minf(left, open_s) if left > 0.0 else open_s)
		var until := int(resp.get("cooldown_until", 0))
		if until > 0 and ds != null:
			ds.breach_cooldown[node.node_id] = until
			end["cooldown"] = ceili((until - Time.get_unix_time_from_system() * 1000.0) / 1000.0)
		end["alert"] = alert_text(resp.get("alert"), outcome, bool(resp.get("local", false)))
	else:
		end["error"] = BridgeApi.err_code(resp)   # Мост отказал: ни эдди, ни хранилищ
		push_warning("[vault-breach] run.breach %s #%d: %s" % [session, att.n, end["error"]])
	if resp.get("local", false):
		for slot in opened:
			node.open_vault(slot, session, float(node.settings.get("vault_open_sec", 60.0)))
	end["opened"] = opened
	if outcome == BreachRules.FAIL and node.is_graph_node():
		node.raise_alert(float(node.settings.get("alert_per_fail", 0.0)))
	node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, end))
	node.event.emit({"kind": "breach_end", "session": session, "vault": att.vault, "n": att.n, "outcome": outcome, "early": att.early,
		"opened": opened, "ok": resp.get("ok", false), "error": end.get("error", "")})
	node._push_shards()
	if node.bridge != null and ds != null and node._sessions.get(session) == ds:
		node._load_deck(session)   # эдди забега изменились


## Строка про сигнал СБ для итога. alert — ответ Моста (null — сигнала не будет, словарь с send_at — будет).
static func alert_text(alert: Variant, outcome: String, local: bool) -> String:
	if local:
		return ""
	if alert is Dictionary:
		var sec := maxi(ceili((float((alert as Dictionary).get("send_at", 0)) - Time.get_unix_time_from_system() * 1000.0) / 1000.0), 0)
		return "СБ получит сигнал сейчас" if sec < 30 else "СБ получит сигнал через %d мин" % ceili(sec / 60.0)
	return "сигнала СБ нет" if outcome != "" else ""


static func _unique(a: Array) -> Array:
	var out: Array = []
	for x in a:
		if not out.has(x):
			out.append(x)
	return out


func _send_no(session: String, deny: Dictionary) -> void:
	var msg := {"kind": WorldMsg.EV_BK_NO}
	msg.merge(deny)
	node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, msg))
