class_name ProtoClient
extends Node
## Клиент прототипа (V3), общий для Pico 4 и плоской сборки: сцена, XR-риг, сеть, журнал в файл.
## Журнал (user://logs/netrun-*.log): start, mode, xr, comfort (+ comfort.warn), rig.recenter, rig.teleport, teleport.denied,
## net.* (в том числе net.config, net.reconnect), grab.*, breach.* (взлом хранилища: request, start, tap — только отказ или ловушка, end, no, cancel), app.pause/resume, frame.slow.
## Деку на руке дополняют вкладки ЧАТ и ЗВОНКИ (фиктивная связь с телефоном): `phone link=fake|off tabs=N` при старте, `phone.msg thread=…`,
## `phone.call phase=…`, `phone.reply thread=… text=…`, `deck.tab id=…`; в строке `perf` — `deck_redraws=N` (сколько раз дека рисовалась в текстуру).
## Аргументы разработки: `--walk` (плоская сборка: ходьба WASD), `--turn=none|snap|smooth` (режим поворота поверх comfort.cfg),
## `--phone=off` (спрятать вкладки ЧАТ и ЗВОНКИ: остаётся одна ДЕКА; по умолчанию вкладки есть, данные для них — фиктивный сценарий).
## Адрес сервера и токен — из netrun.cfg на очках и аргументов (NetConfig.from_sources); сам токен в журнал не попадает.

const SLOW_LOG_MIN_GAP_MS := 250  # долгие кадры (FrameStats.is_slow) в журнал — не чаще раза в 250 мс (остальные — счётчиком)
## Сводка кадров и отрисовки (строка `perf`) — раз в столько секунд.
const PERF_PERIOD_S := 10.0

var log_file := MbLog.new()
## Где искать netrun.cfg (тесты подставляют свои).
var config_paths: PackedStringArray = NetConfig.default_paths()
var scene: Node3D
var net: NetClient
var trace_audio: TraceAudio
## Настройки комфорта (user://comfort.cfg + аргументы), применённые к ригу.
var comfort: ComfortConfig
## Связь деки с телефоном (пока фиктивная); null при `--phone=off`.
var phone: PhoneLink

## Режимы связи с телефоном: `--phone=` (fake — по умолчанию, off — без вкладок ЧАТ и ЗВОНКИ).
const PHONE_FAKE := "fake"
const PHONE_OFF := "off"

const POS_PERIOD := 0.05  # 20 раз/с: чужие клиенты видят нас со сглаживанием по буферу
## Потеряв связь, клиент возвращается сам: попытка раз в 2 с, не дольше ~2 минут (сервер держит аватар 20 с, дальше — новый забег).
const RECONNECT_SEC := 2.0
const RECONNECT_ATTEMPTS := 60

## Через сколько секунд после сборки узла замерить отрисовку (строка `node.perf`); тесты ставят меньше.
var perf_sample_delay_s := 2.0
var _frame_stats := FrameStats.new()
var _hand_modes := ["", ""]    # чем рисуется каждая рука (HandView.Mode): журнал hand.mode при смене
var _perf_acc := 0.0
var _last_level := -1
var _pos_acc := 0.0
var _paused_at_ms := -1
var _slow_skipped := 0
var _last_slow_log_ms := -SLOW_LOG_MIN_GAP_MS


func start(args: PackedStringArray, mode: String, want_xr: bool) -> void:
	log_file.open()
	log_file.log("start", {"mode": mode, "godot": Engine.get_version_info().string, "args": NetConfig.redact_args(args), "log": log_file.path})
	scene = preload("res://client/rig_test_scene.gd").new()
	add_child(scene)
	scene.rig.xr_failed.connect(func(reason: String): log_file.log("xr", {"enabled": false, "reason": reason}))
	scene.rig.away_event.connect(func(kind: String, source: String, sec: float): log_file.log("away." + kind, {"source": source, "sec": snappedf(sec, 0.1)}))
	scene.rig.recentered.connect(func(xr: bool): log_file.log("rig.recenter", {"xr": xr}))
	scene.frame_slow.connect(_on_frame_slow)
	scene.grab_requested.connect(_on_grab_requested)
	scene.shard_stowed.connect(func(id: String): log_file.log("shard.stowed", {"id": id}))
	scene.ice_audio_enabled = true
	_setup_comfort(args)
	_setup_phone(args)
	scene.rig.teleport_attempted.connect(_on_teleport_attempted)
	if want_xr:
		if scene.rig.start_xr():
			log_file.log("xr", {"enabled": true, "reason": "ok", "play_area": "sitting"})
	else:
		log_file.log("xr", {"enabled": false, "reason": "flat_build"})
		scene.rig.recenter()
	var cfg := NetConfig.from_sources(args, config_paths)
	for w in cfg.warnings:
		log_file.log("net.config.warn", {"msg": w})
	log_file.log("net.config", cfg.log_fields())
	if cfg.token.is_empty():
		log_file.log("net.skip", {"reason": "no_token", "looked": " ".join(config_paths)})
		return
	net = NetClient.new()
	net.name = "Net"
	add_child(net)
	net.connected.connect(func(): log_file.log("net.connected", {"host": cfg.host, "port": cfg.port}))
	net.rejected.connect(func(): log_file.log("net.rejected", {"host": cfg.host, "port": cfg.port}))
	net.disconnected.connect(func(): log_file.log("net.disconnected", {"host": cfg.host, "port": cfg.port}))
	net.auto_reconnect_sec = RECONNECT_SEC
	net.auto_reconnect_attempts = RECONNECT_ATTEMPTS
	net.reconnecting.connect(func(attempt: int): log_file.log("net.reconnect", {"host": cfg.host, "port": cfg.port, "attempt": attempt}))
	net.reconnect_gave_up.connect(func(): log_file.log("net.gave_up", {"host": cfg.host, "port": cfg.port, "attempts": RECONNECT_ATTEMPTS}))
	scene.rig.exit_requested.connect(func(_reason: String): net.stop_reconnect())  # вышли сами: сервер закроет забег, возвращаться некуда
	net.state_received.connect(_on_state)
	net.avatars_received.connect(func(msg: Dictionary): scene.apply_avatars(msg))
	net.event_received.connect(_on_event)
	scene.daemon_use_requested.connect(func(id: String): net.request_use(id))
	scene.leave_requested.connect(func(): net.request_leave())
	scene.breach_start_requested.connect(func(vault: String, ids: Array):
		if net.request_breach(vault, ids):
			log_file.log("breach.request", {"vault": vault, "daemons": ids.size()}))
	scene.breach_tap_requested.connect(func(cell: Vector2i): net.request_breach_tap(cell))
	scene.charge_requested.connect(func(id: String):
		if net.request_charge(id):
			log_file.log("charge.request", {"daemon": id}))
	scene.charge_cell_tapped.connect(func(cell: Vector2i): net.request_breach_tap(cell))
	scene.charge_cancel_requested.connect(func():
		net.request_breach_cancel()
		log_file.log("charge.cancel"))
	scene.breach_cancel_requested.connect(func():
		net.request_breach_cancel()
		log_file.log("breach.cancel"))
	scene.give_list_requested.connect(func(): net.request_give_list())
	scene.give_requested.connect(_on_give_requested)
	net.grab_confirmed.connect(_on_grab_confirmed)
	net.grab_denied.connect(_on_grab_denied)
	net.teleport_denied.connect(_on_teleport_denied)
	log_file.log("net.connect", {"host": cfg.host, "port": cfg.port})
	net.start_client(cfg)


## Комфорт: файл user://comfort.cfg (необязателен), поверх него — аргументы разработки. Итог — строка `comfort` в журнале.
func _setup_comfort(args: PackedStringArray) -> void:
	comfort = ComfortConfig.load_file()
	var walk := false
	for a in args:
		if a == "--walk":
			walk = true
		elif a.begins_with("--turn="):
			var m := a.trim_prefix("--turn=")
			if m == RigMath.TURN_MODE_NONE or m == RigMath.TURN_MODE_SMOOTH or m == RigMath.TURN_MODE_SNAP:
				comfort.turn_mode = m
			else:
				comfort.warnings.append("--turn=: допустимо none, smooth или snap, получено «%s»" % m)
	comfort.apply_to(scene.rig)
	scene.rig.walk_enabled = walk
	for w in comfort.warnings:
		log_file.log("comfort.warn", {"msg": w})
	var fields := comfort.log_fields()
	fields["walk"] = walk
	log_file.log("comfort", fields)


## Режим связи с телефоном из аргументов: {mode: PHONE_FAKE | PHONE_OFF, warning: String}. Без аргумента — fake; неизвестное значение —
## fake с предупреждением (не молчим и не падаем).
static func phone_mode(args: PackedStringArray) -> Dictionary:
	var mode := PHONE_FAKE
	var warning := ""
	for a in args:
		if a.begins_with("--phone="):
			var v := a.trim_prefix("--phone=")
			if v == PHONE_OFF:
				mode = PHONE_OFF
			elif v == PHONE_FAKE:
				mode = PHONE_FAKE
			else:
				mode = PHONE_FAKE
				warning = "--phone=: допустимо fake или off, получено «%s»" % v
	return {"mode": mode, "warning": warning}


## Вкладки ЧАТ и ЗВОНКИ деки: связь с телефоном (пока фиктивный сценарий) и строки в журнал. `--phone=off` — вкладок нет.
func _setup_phone(args: PackedStringArray) -> void:
	var m := phone_mode(args)
	if not str(m["warning"]).is_empty():
		log_file.log("phone.warn", {"msg": m["warning"]})
	var deck: DeckPanel = scene.world_ui.deck
	if m["mode"] == PHONE_OFF:
		phone = null
		scene.world_ui.set_phone(null)
	else:
		phone = FakePhoneLink.new(-1.0, true, true)   # сценарий идёт по кругу: очки надевают не сразу после запуска
		scene.world_ui.set_phone(phone)
		phone.message_received.connect(func(thread_id: String, _msg: Dictionary): log_file.log("phone.msg", {"thread": thread_id}))
		phone.call_changed.connect(func(st: Dictionary): log_file.log("phone.call", {"phase": st["phase"], "peer": st["peer"], "muted": st["muted"]}))
		deck.tab_changed.connect(func(id: String): log_file.log("deck.tab", {"id": id}))
		deck.reply_sent.connect(func(thread_id: String, text: String): log_file.log("phone.reply", {"thread": thread_id, "text": text}))
	log_file.log("phone", {"link": m["mode"], "tabs": deck.tab_ids().size()})


func _fmt_xz(p: Vector3) -> String:
	return "%.1f,%.1f" % [p.x, p.z]


## Игрок отпустил стик прицела. Риг переедет сам (моргание), здесь — просьба серверу и журнал.
func _on_teleport_attempted(from: Vector3, to: Vector3, ok: bool, reason: String) -> void:
	log_file.log("rig.teleport", {"from": _fmt_xz(from), "to": _fmt_xz(to), "dist": snappedf(NodeLayout.flat_distance(from, to), 0.1), "ok": ok,
		"face": snappedf(scene.rig.pending_face_deg() if ok else 0.0, 0.1)})
	if not ok:
		log_file.log("teleport.denied", {"reason": reason, "by": "client"})
	elif net != null and net.is_connected_to_world:
		net.request_teleport(to)  # без связи двигаемся только у себя: сервер сверит позу, когда связь вернётся


## Сервер отказал: риг возвращается туда, где аватар на сервере.
func _on_teleport_denied(reason: String, server_pos: Vector3, left: float) -> void:
	log_file.log("teleport.denied", {"reason": reason, "by": "server", "left": snappedf(left, 0.01), "at": _fmt_xz(server_pos)})
	scene.rig.apply_teleport_denial(reason, server_pos, left)


## Снимок узла: интерфейс, ICE и звук получают данные с сервера. Свою позицию клиент шлёт сам (20 раз/с).
func _on_state(state: Dictionary) -> void:
	scene.apply_state(state)
	var level := int(state.get("level", 0))
	if level != _last_level:
		log_file.log("trace.level", {"level": level, "value": snappedf(float(state.get("trace", 0.0)), 0.1)})
		_last_level = level
	if trace_audio == null:  # звук — только когда есть связь с сервером и снимки
		trace_audio = TraceAudio.new()
		add_child(trace_audio)
	trace_audio.set_level(level)


func _on_event(ev: Dictionary) -> void:
	if ev.get("kind") != WorldMsg.EV_BK_TICK:   # bk_tick идёт раз в секунду и на каждый тап: в журнал — только отказы и ловушки (breach.tap)
		log_file.log("node.event", {"kind": ev.get("kind", ""), "reason": ev.get("reason", ""), "daemon": ev.get("daemon", ""), "ok": ev.get("ok", "")})
	match str(ev.get("kind", "")):
		WorldMsg.EV_NODE:
			var built_at := Time.get_ticks_usec()
			scene.apply_node(ev)
			var build_ms := snappedf((Time.get_ticks_usec() - built_at) / 1000.0, 0.1)
			log_file.log("graph.node", {"node": ev.get("node", ""), "tier": ev.get("tier", ""), "arrive": ev.has("arrive")})
			_log_node_perf(str(ev.get("node", "")), str(ev.get("tier", "")), build_ms, built_at)
		WorldMsg.EV_TUNNEL:
			scene.begin_tunnel(str(ev.get("title", "")), float(ev.get("sec", 0.0)))
			log_file.log("graph.tunnel", {"from": ev.get("from", ""), "to": ev.get("to", ""), "sec": ev.get("sec", 0.0)})
		WorldMsg.EV_SHARDS:
			scene.apply_shards(ev.get("shards", []))
		WorldMsg.EV_DECK:
			scene.apply_deck(ev)
			log_file.log("deck.info", {"ram": ev.get("ram", 0), "default": ev.get("ram_default", false), "used": ev.get("used", 0),
				"programs": (ev.get("daemons", []) as Array).size(), "loot": (ev.get("loot", []) as Array).size(), "eddies": ev.get("eddies", 0)})
		WorldMsg.EV_DAEMON:
			scene.apply_daemon_result(ev)
		WorldMsg.EV_BK:
			scene.apply_breach_event(ev)
			if ev.get("mode", "") == WorldMsg.MODE_CHARGE:
				log_file.log("charge.start", {"daemon": ev.get("daemon", ""), "tier": ev.get("tier", ""), "grid": (ev.get("grid", {}) as Dictionary).get("size", 0), "sec": ev.get("sec", 0)})
			else:
				log_file.log("breach.start", {"vault": ev.get("vault", ""), "n": ev.get("n", 0), "tier": ev.get("tier", ""), "grid": (ev.get("grid", {}) as Dictionary).get("size", 0), "sec": ev.get("sec", 0)})
		WorldMsg.EV_BK_TICK:
			scene.apply_breach_event(ev)
			if ev.has("cell") and (not bool(ev.get("ok", true)) or bool(ev.get("trap", false))):
				log_file.log("charge.tap" if ev.get("mode", "") == WorldMsg.MODE_CHARGE else "breach.tap", {"ok": ev.get("ok", false), "trap": ev.get("trap", false), "left": ev.get("left", 0)})
		WorldMsg.EV_BK_END:
			scene.apply_breach_event(ev)
			if ev.get("mode", "") == WorldMsg.MODE_CHARGE:
				log_file.log("charge.end", {"daemon": ev.get("daemon", ""), "outcome": ev.get("outcome", ""), "charged": ev.get("charged", false), "early": ev.get("early", ""), "left": ev.get("left", 0)})
			else:
				log_file.log("breach.end", {"outcome": ev.get("outcome", ""), "early": ev.get("early", ""), "eddies": ev.get("eddies", 0), "opened": (ev.get("opened", []) as Array).size(), "error": ev.get("error", "")})
		WorldMsg.EV_BK_NO:
			scene.apply_breach_event(ev)
			log_file.log("charge.no" if ev.get("mode", "") == WorldMsg.MODE_CHARGE else "breach.no", {"reason": ev.get("reason", "")})
		WorldMsg.EV_GIVE_LIST:
			scene.apply_give_list(ev)
			log_file.log("give.list", {"runners": (ev.get("runners", []) as Array).size()})
		WorldMsg.EV_GIVE:
			scene.apply_give(ev)
			log_file.log("give.result", {"dir": ev.get("dir", ""), "ok": ev.get("ok", false), "item": ev.get("item", ""), "via": ev.get("via", ""), "error": ev.get("error", "")})
		WorldMsg.EV_PORTAL_DENIED:
			scene.show_portal_denied(ev)
			log_file.log("graph.portal_denied", {"to": ev.get("to", ""), "reason": ev.get("reason", "")})
	if ev.get("kind") == WorldMsg.EV_ENDED:
		net.stop_reconnect()  # забег закончился: сервер закроет связь, возвращаться некуда
		scene.show_ended(str(ev.get("reason", "")))
		if ev.get("reason") == ExitLogic.REASON_FLATLINE:
			if trace_audio != null:
				trace_audio.set_level(TraceAudio.FLATLINE)  # фон уже пропадает; добавляем падающий тон
			add_child(FlatlineAudio.new())


func _process(delta: float) -> void:
	if scene != null:
		_log_hand_modes()
		_frame_stats.add(delta)
		_perf_acc += delta
		if _perf_acc >= PERF_PERIOD_S:
			_perf_acc = 0.0
			_log_perf()
	if net == null or not net.is_connected_to_world:
		return
	_pos_acc += delta
	if _pos_acc >= POS_PERIOD:
		_pos_acc = 0.0
		var p: Vector3 = scene.rig.global_position
		var floor_pt := Vector3(p.x, 0.0, p.z)
		net.send_pos(floor_pt, current_pose(floor_pt))


## Поза тела для других игроков: камера и рамки ладоней в осях мира от точки пола (ту же (x, 0, z) сервер знает из `pos`). Рука без позы контроллера
## (frame_valid ложно: контроллера нет, трекинг кистей в рамку и сгибы пока не превращается) в позу не попадает.
func current_pose(floor_pt: Vector3) -> AvatarPose:
	var hands: Array = [null, null]
	var views := [scene.rig.left_hand_view, scene.rig.right_hand_view]
	for side in 2:
		var hv: HandView = views[side]
		if hv != null and hv.frame_valid:
			hands[side] = {"frame": hv.global_transform * hv.frame_palm, "trigger": hv.frame_trigger, "hold": hv.frame_hold}
	return AvatarPose.from_world(scene.rig.camera.global_transform, floor_pt, hands)


func _on_give_requested(item_id: String, to: Dictionary) -> void:
	var sent := net != null and net.request_give(item_id, to)
	log_file.log("give.request", {"item": item_id, "via": WorldMsg.VIA_RUNNER if to.has("runner") else WorldMsg.VIA_PHONE, "sent": sent})
	if not sent:
		scene.apply_give({"kind": WorldMsg.EV_GIVE, "dir": WorldMsg.GIVE_OUT, "ok": false, "item": item_id, "error": WorldMsg.GIVE_UNAVAILABLE})


func _on_grab_requested(object_id: String) -> void:
	if net != null and net.request_grab(object_id):
		log_file.log("grab.request", {"id": object_id})
	else:
		log_file.log("grab.denied", {"id": object_id, "reason": "no_connection"})
		scene.deny_grab()


func _on_grab_confirmed(object_id: String) -> void:
	log_file.log("grab.confirmed", {"id": object_id})
	scene.confirm_grab()


func _on_grab_denied(object_id: String, reason: String) -> void:
	log_file.log("grab.denied", {"id": object_id, "reason": reason})
	scene.deny_grab()


## Чем рисуется каждая рука: controller (поза grip контроллера), tracked (трекинг кистей), none (нет позы). Строка hand.mode — при смене.
func _log_hand_modes() -> void:
	var views := [scene.rig.left_hand_view, scene.rig.right_hand_view]
	for i in 2:
		var hv: HandView = views[i]
		if hv == null:
			continue
		var name: String = HandView.Mode.keys()[hv.mode].to_lower()
		if name != _hand_modes[i]:
			_hand_modes[i] = name
			log_file.log("hand.mode", {"hand": "left" if i == 0 else "right", "mode": name})


## Строка `perf`: кадров за окно, среднее и наибольшее время кадра, долгих кадров, вызовов отрисовки/примитивов/объектов в кадре.
func _log_perf() -> void:
	var fields := _frame_stats.take()
	fields.merge(_render_info())
	fields["deck_redraws"] = scene.world_ui.deck.redraw_count
	log_file.log("perf", fields)


## Счётчики отрисовки прошлого кадра (в безэкранном запуске — нули).
func _render_info() -> Dictionary:
	return {
		"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
	}


## Строка `node.perf` после входа в узел: сколько ушло на сборку (build_ms) и на первую отрисовку (first_frame_ms — до конца
## первого кадра, где первый показ шейдеров может подвиснуть), потом, через perf_sample_delay_s, во что обходится готовый узел.
func _log_node_perf(node: String, tier: String, build_ms: float, built_at_usec: int) -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame  # без экрана кадр не рисуется и frame_post_draw не приходит
	else:
		await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return  # клиент закрыли, не дождавшись кадра
	var first_ms := snappedf((Time.get_ticks_usec() - built_at_usec) / 1000.0, 0.1)
	await get_tree().create_timer(perf_sample_delay_s).timeout
	if not is_inside_tree():
		return
	var fields := {"node": node, "tier": tier, "build_ms": build_ms, "first_frame_ms": first_ms}
	fields.merge(_render_info())
	log_file.log("node.perf", fields)


func _on_frame_slow(ms: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_slow_log_ms < SLOW_LOG_MIN_GAP_MS:
		_slow_skipped += 1
		return
	log_file.log("frame.slow", {"ms": ms, "limit_ms": snappedf(FrameStats.SLOW_SEC * 1000.0, 0.01), "skipped": _slow_skipped})
	_slow_skipped = 0
	_last_slow_log_ms = now


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_paused_at_ms = Time.get_ticks_msec()
			log_file.log("app.pause")
		NOTIFICATION_APPLICATION_RESUMED:
			var slept := (Time.get_ticks_msec() - _paused_at_ms) / 1000.0 if _paused_at_ms >= 0 else 0.0
			log_file.log("app.resume", {"slept_sec": slept, "connected": net != null and net.is_connected_to_world})
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			log_file.log("app.stop")
