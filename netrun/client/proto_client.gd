class_name ProtoClient
extends Node
## Клиент прототипа (V3), общий для Pico 4 и плоской сборки: сцена, XR-риг, сеть, журнал в файл.
## Журнал (user://logs/netrun-*.log): start, mode, xr, rig.recenter, net.*, grab.*, app.pause/resume, frame.slow.

const SLOW_LOG_MIN_GAP_MS := 250  # кадры дольше 1/72 с в журнал — не чаще раза в 250 мс (остальные — счётчиком)

var log_file := MbLog.new()
var scene: Node3D
var net: NetClient

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
	net.grab_confirmed.connect(_on_grab_confirmed)
	net.grab_denied.connect(_on_grab_denied)
	log_file.log("net.connect", {"host": cfg.host, "port": cfg.port})
	net.start_client(cfg)


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
