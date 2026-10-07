extends SceneTree
## Один забег бота для долгого прогона (tools/soak.sh): сдаёт деку в Мост (роль test), подтверждает сессию, проходит узел
## ботом (BotClient) и ждёт, пока Мост закроет сессию. Печатает `[soak-run] ...` и выходит. Процесс на забег — чтобы убить
## бота посреди забега было просто, а память и сокеты не копились.
## `godot --headless --path netrun -s res://tools/soak_run.gd -- --bridge=ws://127.0.0.1:7410/netrun/v1 --key=<ключ test>
##   --runner=<ключ игрока> --terminal=t01 --token=<токен> --items=<предмет1>,<предмет2> --host=127.0.0.1 --port=7777
##   --scenario=ghost_run|exposed_run [--chaos=emergency|drop_return|drop_gone] [--chaos-after=2] [--no-shard]
##   [--net-loss=0.05] [--net-delay-ms=60] [--net-jitter-ms=30] [--tag=bN-rK] [--grace=20] [--wait-closed=60]
##   [--start-slot=N] (первый ход — на свободную клетку возле входа узла, своя у каждого N) [--ghost-daemon=<id предмета>] (чем бот включает Призрака)`
## Код выхода: 0 — забег прошёл и сессия закрыта; 3 — Мост отказал в деке; 4 — Мост/сервер мира недоступны; 5 — сессия не закрылась вовремя;
## 6 — бот завис (timeout:*). Итоговая строка: `[soak-run] tag=… scenario=… chaos=… result=… outcome=… dur=…s reconnects=… net=…`.

var _bridge: BridgeClient
var _args := {}
var _bot: BotClient
var _t0 := 0.0
var _finished := false


func _initialize() -> void:
	Engine.max_fps = 60
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_t0 = Time.get_ticks_msec() / 1000.0
	_bridge = BridgeClient.new(str(_args.get("bridge", "ws://127.0.0.1:7410/netrun/v1")), str(_args.get("key", "")), "soak-" + str(_args.get("tag", "x")))
	_bridge.role = "test"
	_bridge.start()
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_bridge.poll()
	return false


func _tag() -> String:
	return str(_args.get("tag", "?"))


func _done(code: int, what: String, result: String = "-", outcome: String = "-") -> void:
	if _finished:
		return
	_finished = true
	var net := "-"
	var reconnects := 0
	if _bot != null and _bot.net != null:
		net = "up_drop=%d,down_drop=%d" % [_bot.net.impair_dropped_up, _bot.net.impair_dropped_down]
		reconnects = _bot.reconnects
	print("[soak-run] tag=%s scenario=%s chaos=%s %s result=%s outcome=%s dur=%.1fs reconnects=%d net=%s" % [
		_tag(), _args.get("scenario", "?"), _args.get("chaos", "-"), what, result, outcome,
		Time.get_ticks_msec() / 1000.0 - _t0, reconnects, net])
	quit(code)


func _run() -> void:
	create_timer(float(_args.get("limit", "170"))).timeout.connect(func(): _done(6, "limit", "timeout:soak_run"))
	var until := Time.get_ticks_msec() + 20000
	while not _bridge.is_ready():
		if Time.get_ticks_msec() > until:
			_done(4, "bridge_down")
			return
		await create_timer(0.2).timeout
	var terminal := str(_args.get("terminal", ""))
	# Терминал ещё занят прошлым забегом (его бота убили): ждём, пока сервер мира закроет сессию по окну возврата.
	var wait_until := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < wait_until and await _terminal_busy(terminal):
		await create_timer(1.0).timeout
	# Узел в локдауне (после выброса ICE): вход откажет, а отказ возвращает деку на телефон — запас предметов тратится зря.
	var lock_until := Time.get_ticks_msec() + 60000
	var entry_node := NodeGraph.load_file().entry_for(terminal)   # узел, куда сервер мира ведёт этот терминал (graph.json)
	while Time.get_ticks_msec() < lock_until:
		var nd: Dictionary = await _bridge.get_doc("node", entry_node)
		var locked_ms := int(nd.get("doc", {}).get("data", {}).get("lockdown_until", 0)) - int(Time.get_unix_time_from_system() * 1000.0)
		if locked_ms <= 0:
			break
		await create_timer(minf(locked_ms / 1000.0 + 0.2, 2.0)).timeout
	var items: Array = str(_args.get("items", "")).split(",", false)
	var sub: Dictionary = await _bridge._request("op.submit_deck", {
		"rid": "enter:soak-%s-%d" % [_tag(), Time.get_ticks_msec()], "runner": str(_args.get("runner", "")), "callsign": "Soak",
		"terminal": terminal, "items": items, "protected": items[0]})
	if not sub.get("ok", false):
		_done(3, "submit=" + BridgeApi.err_code(sub))
		return
	var session := str(sub.get("session", ""))
	var conf: Dictionary = await _bridge.session_confirm(session, terminal)
	if not conf.get("ok", false):
		_done(3, "confirm=" + BridgeApi.err_code(conf))
		return
	_start_bot()
	var result: String = await _bot_result()
	if result.begins_with("timeout:connect"):
		_done(4, "world_down session=" + session, result)
		return
	var stuck := result.begins_with("timeout:")
	# Закрывает сессию сервер мира: сразу при выходе или по окну возврата (обрыв без возврата, убитый бот).
	var close_until := Time.get_ticks_msec() + int(float(_args.get("wait-closed", "60")) * 1000.0)
	var outcome := "-"
	while Time.get_ticks_msec() < close_until:
		var s: Dictionary = await _bridge.get_doc("session", session)
		if s.get("ok", false) and str(s["doc"]["data"].get("state")) == "closed":
			outcome = str(s["doc"]["data"].get("outcome"))
			_done(6 if stuck else 0, "session=" + session, result, outcome)
			return
		await create_timer(1.0).timeout
	_done(5, "unclosed session=" + session, result)


func _terminal_busy(terminal: String) -> bool:
	var r: Dictionary = await _bridge.list_docs("session")
	for d in r.get("docs", []):
		var data: Dictionary = d["data"]
		if str(data.get("terminal")) == terminal and str(data.get("state")) != "closed":
			return true
	return false


func _start_bot() -> void:
	_bot = BotClient.new()
	_bot.name = "Bot"
	_bot.reconnect = true
	_bot.verbose = false
	_bot.no_shard = "no-shard" in _args
	_bot.chaos = str(_args.get("chaos", ""))
	_bot.chaos_after = float(_args.get("chaos-after", "2"))
	_bot.start_slot = int(_args.get("start-slot", "-1"))
	if _args.has("ghost-daemon"):
		_bot.ghost_daemon = str(_args["ghost-daemon"])
	root.add_child(_bot)
	var cfg := NetConfig.new()
	cfg.host = str(_args.get("host", "127.0.0.1"))
	cfg.port = int(_args.get("port", "7777"))
	cfg.token = "%s:%s" % [_args.get("terminal", ""), _args.get("token", "")]
	cfg.grace_sec = float(_args.get("grace", "20"))
	var kind := BotClient.Scenario.EXPOSED_RUN if str(_args.get("scenario", "ghost_run")) == "exposed_run" else BotClient.Scenario.GHOST_RUN
	_bot.start(cfg, kind)
	_bot.net.impair_loss = float(_args.get("net-loss", "0"))
	_bot.net.impair_delay_ms = int(_args.get("net-delay-ms", "0"))
	_bot.net.impair_jitter_ms = int(_args.get("net-jitter-ms", "0"))


func _bot_result() -> String:
	while _bot.result.is_empty():
		await create_timer(0.2).timeout
	return _bot.result
