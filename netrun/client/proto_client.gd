class_name ProtoClient
extends Node
## Клиент прототипа (V3), общий для Pico 4 и плоской сборки: сцена, XR-риг, сеть, журнал в файл.
## Журнал (user://logs/netrun-*.log): start, mode, xr, comfort (+ comfort.warn), rig.recenter, rig.teleport, teleport.denied,
## net.* (в том числе net.config, net.reconnect), grab.*, app.pause/resume, frame.slow.
## Аргументы разработки: `--walk` (плоская сборка: ходьба WASD), `--turn=none|snap|smooth` (режим поворота поверх comfort.cfg).
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

const POS_PERIOD := 0.05  # 20 раз/с: чужие клиенты видят нас со сглаживанием по буферу
## Потеряв связь, клиент возвращается сам: попытка раз в 2 с, не дольше ~2 минут (сервер держит аватар 20 с, дальше — новый забег).
const RECONNECT_SEC := 2.0
const RECONNECT_ATTEMPTS := 60

## Через сколько секунд после сборки узла замерить отрисовку (строка `node.perf`); тесты ставят меньше.
var perf_sample_delay_s := 2.0
var _frame_stats := FrameStats.new()
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
	scene.rig.recentered.connect(func(xr: bool): log_file.log("rig.recenter", {"xr": xr}))
	scene.frame_slow.connect(_on_frame_slow)
	scene.grab_requested.connect(_on_grab_requested)
	scene.ice_audio_enabled = true
	_setup_comfort(args)
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


func _fmt_xz(p: Vector3) -> String:
	return "%.1f,%.1f" % [p.x, p.z]


## Игрок отпустил стик прицела. Риг переедет сам (моргание), здесь — просьба серверу и журнал.
func _on_teleport_attempted(from: Vector3, to: Vector3, ok: bool, reason: String) -> void:
	log_file.log("rig.teleport", {"from": _fmt_xz(from), "to": _fmt_xz(to), "dist": snappedf(NodeLayout.flat_distance(from, to), 0.1), "ok": ok})
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
		net.send_pos(Vector3(p.x, 0.0, p.z))


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


## Строка `perf`: кадров за окно, среднее и наибольшее время кадра, долгих кадров, вызовов отрисовки/примитивов/объектов в кадре.
func _log_perf() -> void:
	var fields := _frame_stats.take()
	fields.merge(_render_info())
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
