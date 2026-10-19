class_name RunOutcome
extends RefCounted
## Исход забега и запись в Мост на сервере мира: закрытие сессии узлом (run.finish с повторами), пометка finish в session.data.world,
## ожидание решения мастера перед флэтлайном и охота Black ICE (флаг «под охотой» и её запись в world.hunt). Вынесено из GrayNode
## (рефакторинг, поведение, порядок await и сообщения те же). Держит ссылку на узел (как NodeAlarm, LayoutDevices и ShardVaults):
## сессии, сеть, Мост, события и журнал Black ICE остаются там — здесь только состояние исхода и охоты и правила их записи.
## Сигнал event (finished, flatline_gate, waiting_master, gate_overdue, hunt, exit …) по-прежнему идёт через node.event.
## Публичные имена GrayNode (_finish_in_bridge, _mark_finish, _end, release_session, is_hunted …) — тонкие делегаты сюда.
## Статические outcome_plan / is_transient / is_moves_stale / finish_moves и константы FINISH_* / HUNT_* остались в GrayNode
## (их зовут снаружи как GrayNode.*).

var _node: GrayNode
var finishing: Dictionary = {}       # сессия -> true: её исход уже уходит в Мост (вход закрыт, terminal.auth не отдаёт)
var hunted: Dictionary = {}          # сессия -> true, пока за ней идёт охота Black ICE
var hunt_retry_sec := GrayNode.HUNT_RETRY_SEC # пауза между попытками записи охоты (тест ставит поменьше)
var hunt_written: Dictionary = {}    # сессия -> bool: что Мост подтвердил в world.hunt (нет записи — не писали, то есть false)
var hunt_writing: Dictionary = {}    # сессия -> true, пока идёт запись: она одна на сессию и сама перечитывает нужное значение
var flat_disconnect: Dictionary = {} # сессия -> true: Black ICE догнал в окне возврата после обрыва («обрыв до флэтлайна»)


func _init(owner_node: GrayNode) -> void:
	_node = owner_node


## Охота Black ICE → флаг «под охотой» у NetServer (аварийный выход сожжёт деку). Каждый тик: выход не ждёт 0,1 с.
func _update_hunts() -> void:
	for session in _node._live_sessions():
		var black := _node.black_ice()   # охотится только Black ICE логова: охота общая, не за конкретной сессией
		var is_hunted_now := black != null and black.is_hunting()
		if is_hunted_now != bool(hunted.get(session, false)):
			hunted[session] = is_hunted_now
			_node.net.set_under_hunt(session, is_hunted_now)
			_node.event.emit({"kind": "hunt", "session": session, "on": is_hunted_now})
			_sync_hunt(session)


func _end(session: String, exit_reason: String, kind: String) -> void:
	if not _node.net.has_avatar(session):
		return
	if _node.is_graph_node():
		_node.alarm_event("eject")
		if kind == "ice_eject" and _node.bridge == null and not _node.is_tutorial():
			_node.lock_for(float(_node.settings["lockdown_sec"]))  # с Мостом локдаун выставляет он (run.finish soft_ice)
	_node.event.emit({"kind": kind, "session": session})
	_node.net.end_session(session, exit_reason)


func _on_exit_event(ev: Dictionary) -> void:
	_node._portal_state.erase(ev["session"])
	# Граф: сигнал приходит всем узлам, забег закрывает тот, чей игрок это был (метка _exiting из _on_avatar_removed).
	if not _node._exiting.erase(ev["session"]) and _node.is_graph_node():
		return
	_node.event.emit({"kind": "exit", "session": ev["session"], "reason": ev["reason"]})
	finishing[ev["session"]] = true
	if ev["reason"] == ExitLogic.REASON_FLATLINE:
		ev = ev.duplicate()
		ev["disconnect"] = bool(flat_disconnect.get(ev["session"], false))
		flat_disconnect.erase(ev["session"])
	_finish_in_bridge(ev)


## Охота Black ICE в session.data.world.hunt: Мост по true шлёт быстрое событие ice.hunt, конец охоты событием не является.
## Пишем смену, а не каждый тик: нужное значение берётся из hunted, подтверждённое Мостом — из hunt_written. Писатель один на
## сессию: пока он ждёт Мост, смена охоты только меняет hunted, а он по возвращении видит свежее значение (true и сразу false
## не обгоняют друг друга и очередь запросов не растёт). Мост недоступен — HUNT_ATTEMPTS попыток и отказ без записи: охота не
## критична для хода, а следующая смена охоты запишется заново.
func _sync_hunt(session: String) -> void:
	if _node.bridge == null or not _node.synced or hunt_writing.has(session):
		return
	hunt_writing[session] = true
	while bool(hunted.get(session, false)) != bool(hunt_written.get(session, false)):
		var want := bool(hunted.get(session, false))
		if not await _put_hunt(session, want):
			break
		hunt_written[session] = want
	hunt_writing.erase(session)
	if not _node._sessions.has(session):
		hunt_written.erase(session)  # игрока в узле нет: помнить нечего


## Один раз записать world.hunt (чтение-правка-запись, остальные поля world сохраняются). Повтор при version_conflict и обрыве
## связи, но не больше HUNT_ATTEMPTS. false — не вышло.
func _put_hunt(session: String, hunt: bool) -> bool:
	for attempt in GrayNode.HUNT_ATTEMPTS:
		@warning_ignore("redundant_await")
		var g: Dictionary = await _node.bridge.get_doc(BridgeApi.T_SESSION, session)
		if g.get("ok", false):
			var cur: Dictionary = g["doc"]
			var data: Dictionary = (cur.get("data", {}) as Dictionary).duplicate(true)
			var w: Dictionary = (data.get("world", {}) as Dictionary).duplicate(true) if data.get("world") is Dictionary else {}
			w["hunt"] = hunt
			data["world"] = w
			@warning_ignore("redundant_await")
			var r: Dictionary = await _node.bridge.put_doc(BridgeApi.T_SESSION, session, int(cur["ver"]), data)
			if r.get("ok", false):
				return true
			g = r
		var code := BridgeApi.err_code(g)
		if GrayNode.is_transient(g):
			if not _node.is_inside_tree():
				return false
			await _node.get_tree().create_timer(hunt_retry_sec).timeout
		elif code != "version_conflict":
			push_warning("[gray-node] hunt %s: %s" % [session, code])
			return false
	push_warning("[gray-node] hunt %s: не записано за %d попыток" % [session, GrayNode.HUNT_ATTEMPTS])
	return false


## Пометка в session.data.world: что сервер мира закрывает эту сессию (finish, disconnect). Остальные поля world сохраняются.
## Повтор при version_conflict и обрыве связи; не вышло окончательно (документа нет, отказ) — продолжаем без пометки.
func _mark_finish(session: String, finish: String, disconnect: bool, extra: Dictionary = {}) -> void:
	if _node.bridge == null:
		return
	for attempt in GrayNode.FINISH_ATTEMPTS:
		@warning_ignore("redundant_await")
		var g: Dictionary = await _node.bridge.get_doc(BridgeApi.T_SESSION, session)
		if g.get("ok", false):
			var cur: Dictionary = g["doc"]
			var data: Dictionary = (cur.get("data", {}) as Dictionary).duplicate(true)
			var w: Dictionary = (data.get("world", {}) as Dictionary).duplicate(true) if data.get("world") is Dictionary else {}
			w["finish"] = finish
			w["disconnect"] = disconnect
			w.merge(extra, true)   # например black_log: журнал Black ICE для карточки флэтлайна (поле world непрозрачно для Моста)
			data["world"] = w
			@warning_ignore("redundant_await")
			var r: Dictionary = await _node.bridge.put_doc(BridgeApi.T_SESSION, session, int(cur["ver"]), data)
			if r.get("ok", false):
				return
			g = r
		if not GrayNode.is_transient(g) and BridgeApi.err_code(g) != "version_conflict":
			push_warning("[gray-node] пометка finish %s: %s" % [session, BridgeApi.err_code(g)])
			return
		if not _node.is_inside_tree():
			return
		await _node.get_tree().create_timer(GrayNode.FINISH_RETRY_SEC if GrayNode.is_transient(g) else 0.05).timeout
	push_warning("[gray-node] пометка finish %s не записана" % session)


## «Ждём мастера» перед флэтлайном. Возвращает "approve" (применять), "deny" (пощадить) или "" (узел закрывается).
## Мост сам ведёт срок и решение по таймауту; нам остаётся спрашивать раз в GATE_POLL_SEC, пока он отвечает wait.
## Сбой связи или отказ Моста решения не заменяют: опрос продолжается, исход сами не назначаем (run.finish без Моста
## всё равно не пройдёт). Дольше срока await_timeout_s + запас — запись в журнал и дальше те же опросы.
func _await_master_flatline(session: String) -> String:
	var announced := false
	var summary := "ФЛЭТЛАЙН: %s" % str(_callsign_of(session))
	var started := Time.get_ticks_msec()
	var limit_sec := await _gate_limit_sec()
	var warned_at := 0.0
	var failures := 0
	while _node.is_inside_tree():
		@warning_ignore("redundant_await")
		var r: Dictionary = await _node.bridge.master_gate("flatline", session, _node.node_id, summary)
		if not r.get("ok", false):
			failures += 1
			if failures == 1 or failures % 60 == 0:
				push_warning("[gray-node] master.gate flatline %s: %s (опрос продолжается)" % [session, BridgeApi.err_code(r)])
		else:
			failures = 0
			var mode := str(r.get("mode", "auto"))
			if mode != "wait":
				var decision := str(r.get("decision", "approve")) if r.get("decision") != null else "approve"
				print("[gray-node] flatline ", session, ": ", mode, " ", decision)
				_node.event.emit({"kind": "flatline_gate", "session": session, "mode": mode, "decision": decision})
				return decision
			if not announced:
				announced = true
				print("[gray-node] flatline ", session, ": ждём мастера")
				_node.event.emit({"kind": "waiting_master", "session": session})
		var waited := (Time.get_ticks_msec() - started) / 1000.0
		if waited >= limit_sec + warned_at:
			warned_at += limit_sec
			push_warning("[gray-node] flatline %s: ждём решения уже %d с (срок %d с) — Мост должен решить по таймауту, опрос продолжается" % [session, int(waited), int(limit_sec)])
			_node.event.emit({"kind": "gate_overdue", "session": session, "waited": waited})
		if not _node.is_inside_tree():
			break
		await _node.get_tree().create_timer(GrayNode.GATE_POLL_SEC).timeout
	return ""


## Срок «ждём мастера» из настроек Моста (settings/global.await_timeout_s) плюс запас; нет связи — по умолчанию.
func _gate_limit_sec() -> float:
	var timeout := GrayNode.GATE_DEFAULT_TIMEOUT_SEC
	@warning_ignore("redundant_await")
	var g: Dictionary = await _node.bridge.get_doc("settings", "global")
	if g.get("ok", false):
		var t: Variant = ((g["doc"] as Dictionary).get("data", {}) as Dictionary).get("await_timeout_s")
		if t is int or t is float:
			timeout = maxf(float(t), 1.0)
	return timeout + GrayNode.GATE_GRACE_SEC


func _callsign_of(session: String) -> String:
	if _node.bridge == null:
		return session
	var s: Dictionary = _node.bridge.cached_doc(BridgeApi.T_SESSION, session)
	var cs := str((s.get("data", {}) as Dictionary).get("callsign", ""))
	return cs if cs != "" else session


func _finish_in_bridge(ev: Dictionary) -> void:
	if _node.bridge == null:
		return
	var session: String = ev["session"]
	while int(_node._takes_inflight.get(session, 0)) > 0:
		await _node.get_tree().process_frame
	if ev["reason"] == ExitLogic.REASON_FLATLINE:
		# Пометка в Мосте ДО ожидания: рестарт сервера мира посреди него продолжит этот же флэтлайн (recover).
		var extra := {}
		if _node._black_log.has(session):
			extra["black_log"] = _node._black_log[session]
		await _mark_finish(session, "flatline", bool(ev.get("disconnect", false)), extra)
		var verdict := await _await_master_flatline(session)
		if verdict == "":
			return  # узел закрывается: продолжит следующий процесс по пометке
		if verdict == "deny":
			ev = ev.duplicate()
			ev["reason"] = ExitLogic.REASON_EJECTED  # мастер пощадил до применения: как Soft ICE, без блокировки
			ev["disconnect"] = false
	var plan := GrayNode.outcome_plan(ev)
	# Дека могла измениться между чтением и вызовом (пришёл предмет по op.give_item, протокол 6.5/6.7): Мост отвечает bad_request «не упомянут
	# в moves» и не записывает rid — перечитываем деку, пересобираем moves и шлём тот же rid. Это не новое намерение.
	var r: Dictionary = {}
	for round_no in GrayNode.MOVES_ATTEMPTS:
		var moves := await _collect_moves(session, plan)
		for attempt in GrayNode.FINISH_ATTEMPTS:
			@warning_ignore("redundant_await")
			r = await _node.bridge.run_finish(session, plan["outcome"], _node.node_id, plan["disconnect"], moves)
			if not GrayNode.is_transient(r) or not _node.is_inside_tree():
				break
			await _node.get_tree().create_timer(GrayNode.FINISH_RETRY_SEC).timeout
		if not GrayNode.is_moves_stale(r) or not _node.is_inside_tree():
			break
	print("[gray-node] run.finish ", session, " ", plan["outcome"], ": ", "ok" if r.get("ok", false) else BridgeApi.err_code(r))
	if r.get("ok", false):
		finishing.erase(session)  # сессия закрыта в Мосте: terminal.auth её уже не отдаст
	_node.event.emit({"kind": "finished", "session": session, "outcome": plan["outcome"], "ok": r.get("ok", false)})


## moves исхода по свежему чтению деки и документа сессии. Деление на рабочих и груз — по `session.loaded` (как у Моста); документ сессии
## не получен — запасное правило по origin.
func _collect_moves(session: String, plan: Dictionary) -> Array:
	var listed: Dictionary = {}
	for attempt in GrayNode.FINISH_ATTEMPTS:
		@warning_ignore("redundant_await")
		listed = await _node.bridge.list_docs(BridgeApi.T_ITEM)
		if listed.get("ok", false) or not GrayNode.is_transient(listed) or not _node.is_inside_tree():
			break
		await _node.get_tree().create_timer(GrayNode.FINISH_RETRY_SEC).timeout
	var sdata: Dictionary = {}
	for attempt in GrayNode.FINISH_ATTEMPTS:
		@warning_ignore("redundant_await")
		var sr: Dictionary = await _node.bridge.get_doc(BridgeApi.T_SESSION, session)
		if sr.get("ok", false):
			sdata = (sr["doc"] as Dictionary).get("data", {})
			break
		if not GrayNode.is_transient(sr) or not _node.is_inside_tree():
			break
		await _node.get_tree().create_timer(GrayNode.FINISH_RETRY_SEC).timeout
	return GrayNode.finish_moves(listed.get("docs", []), session, sdata, plan)


## Идёт ли запись охоты в Мост (тест ждёт, пока писатель закончит или сдастся).
func is_hunt_writing() -> bool:
	return not hunt_writing.is_empty()


func is_hunted(session: String) -> bool:
	return bool(hunted.get(session, false))


## Идёт ли в узле охота Black ICE (за кем-то из игроков узла).
func is_hunt_active() -> bool:
	for session in hunted:
		if bool(hunted[session]):
			return true
	return false


## Снять сессию с узла (уходит в тоннель/в другой узел): состояние (trace, дека, перезарядки) возвращается вызывающему целым.
func release_session(session: String) -> DaemonSession:
	var ds: DaemonSession = _node._sessions.get(session)
	if ds == null:
		return null
	_node.breach.end_early(session, "transit")
	_node.charge.end_early(session, "transit")
	_node.decrypt.end_early(session, "transit")
	_node.barrier.end_early(session, "transit")
	_node.shards.close_vaults_of(session)
	var cb: Callable = _node._level_cbs.get(session, Callable())
	if cb.is_valid() and ds.trace.level_changed.is_connected(cb):
		ds.trace.level_changed.disconnect(cb)
	_node._level_cbs.erase(session)
	_node._sessions.erase(session)
	_node._effect_logged.erase(session)
	_node._entered_at.erase(session)
	hunted.erase(session)
	_sync_hunt(session)  # сессия уходит в другой узел: охота этого узла за ней кончилась
	_node._portal_state.erase(session)
	_node.net.set_under_hunt(session, false)
	_node._forget_in_ices(session)
	_node._write_node_state()
	return ds


## Принять сессию с её состоянием: trace и дека те же объекты, что были в прошлом узле (пара к release_session).
func adopt_session(session: String, ds: DaemonSession) -> void:
	_node._sessions[session] = ds
	_node._entered_at[session] = _node._now
	_node._mark_entered_tick(session)
	_node._connect_meter(session, ds.trace)
	print("[gray-node] ", session, " вошёл в ", _node.node_id, " (переход)")
	_node._push_deck(session)
	if _node.bridge != null and _node.synced:
		# Мост читает world.node (где игрок сейчас) и trace_level/effects (сигнал СБ): после перехода пишем их для нового узла.
		merge_world(session, {"connected": _node.net.peer_of(session) != -1, "trace": int(ds.trace.value()), "node": _node.node_id,
			"trace_level": ds.trace.level(), "effects": ds.active_effects(_node._now)})
		_node._write_node_state()


## Уровень trace в session.data.world (trace_level — число TraceMeter.Level, trace — значение, effects — активные GHOST/TIMESKEW/BLACKOUT): Мост по нему решает про сигнал СБ.
## Остальные поля world сохраняются; повтор при version_conflict и обрыве, не вышло окончательно — без записи (уровень не критичен для хода).
func mark_trace_level(session: String, level: int, value: float, effects: Array) -> void:
	for attempt in GrayNode.FINISH_ATTEMPTS:
		@warning_ignore("redundant_await")
		var g: Dictionary = await _node.bridge.get_doc(BridgeApi.T_SESSION, session)
		if g.get("ok", false):
			var cur: Dictionary = g["doc"]
			var data: Dictionary = (cur.get("data", {}) as Dictionary).duplicate(true)
			var w: Dictionary = (data.get("world", {}) as Dictionary).duplicate(true) if data.get("world") is Dictionary else {}
			w["trace_level"] = level
			w["trace"] = int(value)
			w["effects"] = effects
			data["world"] = w
			@warning_ignore("redundant_await")
			var r: Dictionary = await _node.bridge.put_doc(BridgeApi.T_SESSION, session, int(cur["ver"]), data)
			if r.get("ok", false):
				return
			g = r
		if not GrayNode.is_transient(g) and BridgeApi.err_code(g) != "version_conflict":
			push_warning("[gray-node] trace_level %s: %s" % [session, BridgeApi.err_code(g)])
			return
		if not _node.is_inside_tree():
			return


## Слить поля в session.data.world, не трогая остальные (trace_level, effects, finish). Повтор при version_conflict.
func merge_world(session: String, fields: Dictionary) -> void:
	for attempt in 3:
		@warning_ignore("redundant_await")
		var g: Dictionary = await _node.bridge.get_doc(BridgeApi.T_SESSION, session)
		if not g.get("ok", false):
			return
		var cur: Dictionary = g["doc"]
		var data: Dictionary = (cur.get("data", {}) as Dictionary).duplicate(true)
		var w: Dictionary = (data.get("world", {}) as Dictionary).duplicate(true) if data.get("world") is Dictionary else {}
		w.merge(fields, true)
		data["world"] = w
		@warning_ignore("redundant_await")
		var r: Dictionary = await _node.bridge.put_doc(BridgeApi.T_SESSION, session, int(cur["ver"]), data)
		if r.get("ok", false) or BridgeApi.err_code(r) != "version_conflict":
			return
