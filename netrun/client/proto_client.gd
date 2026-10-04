class_name ProtoClient
extends Node
## Клиент прототипа (V3), общий для Pico 4 и плоской сборки: сцена, XR-риг, сеть, журнал в файл.
## Журнал (user://logs/netrun-*.log): start, mode, xr, rig.recenter, net.* (в том числе net.reconnect), grab.*, app.pause/resume, frame.slow.

const SLOW_LOG_MIN_GAP_MS := 250  # кадры дольше 1/72 с в журнал — не чаще раза в 250 мс (остальные — счётчиком)

var log_file := MbLog.new()
var scene: Node3D
var net: NetClient
var trace_audio: TraceAudio

const POS_PERIOD := 0.05  # 20 раз/с: чужие клиенты видят нас со сглаживанием по буферу
## Потеряв связь, клиент возвращается сам: попытка раз в 2 с, не дольше ~2 минут (сервер держит аватар 20 с, дальше — новый забег).
const RECONNECT_SEC := 2.0
const RECONNECT_ATTEMPTS := 60

var _last_level := -1
var _pos_acc := 0.0
var _paused_at_ms := -1
var _slow_skipped := 0
var _last_slow_log_ms := -SLOW_LOG_MIN_GAP_MS


func start(args: PackedStringArray, mode: String, want_xr: bool) -> void:
	log_file.open()
	log_file.log("start", {"mode": mode, "godot": Engine.get_version_info().string, "args": " ".join(args), "log": log_file.path})
	scene = preload("res://client/rig_test_scene.gd").new()
	add_child(scene)
	scene.rig.xr_failed.connect(func(reason: String): log_file.log("xr", {"enabled": false, "reason": reason}))
	scene.rig.recentered.connect(func(xr: bool): log_file.log("rig.recenter", {"xr": xr}))
	scene.frame_slow.connect(_on_frame_slow)
	scene.grab_requested.connect(_on_grab_requested)
	scene.ice_audio_enabled = true
	if want_xr:
		if scene.rig.start_xr():
			log_file.log("xr", {"enabled": true, "reason": "ok", "play_area": "sitting"})
	else:
		log_file.log("xr", {"enabled": false, "reason": "flat_build"})
		scene.rig.recenter()
	var cfg := NetConfig.from_args(args)
	if cfg.token.is_empty():
		log_file.log("net.skip", {"reason": "no_token"})
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
	log_file.log("net.connect", {"host": cfg.host, "port": cfg.port})
	net.start_client(cfg)


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
			scene.apply_node(ev)
			log_file.log("graph.node", {"node": ev.get("node", ""), "tier": ev.get("tier", ""), "arrive": ev.has("arrive")})
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


func _on_frame_slow(ms: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_slow_log_ms < SLOW_LOG_MIN_GAP_MS:
		_slow_skipped += 1
		return
	log_file.log("frame.slow", {"ms": ms, "limit_ms": 1000.0 / 72.0, "skipped": _slow_skipped})
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
