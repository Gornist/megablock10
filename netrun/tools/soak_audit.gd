extends SceneTree
## Проверка Моста во время и после долгого прогона (tools/soak.sh): тревоги, число предметов, открытые сессии.
## `godot --headless --path netrun -s res://tools/soak_audit.gd -- --bridge=ws://127.0.0.1:7410/netrun/v1 --key=<ключ world> [--items=<сколько должно быть>]`
## Печатает `[audit] alerts_auditor=N alerts_other=M items=K sessions_open=O sessions_closed=C outcomes=a:1,b:2` и по строке `[audit] alert <id> <kind> <msg>` на тревогу.
## Код: 0 — Мост ответил (решает вызывающий), 2 — Мост не отвечает, 1 — число предметов не сошлось с --items.

var _client: BridgeClient
var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_client = BridgeClient.new(str(_args.get("bridge", "ws://127.0.0.1:7410/netrun/v1")), str(_args.get("key", "")), "soak-audit")
	_client.start()
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_client.poll()
	return false


func _run() -> void:
	var until := Time.get_ticks_msec() + 20000
	while not _client.is_ready():
		if Time.get_ticks_msec() > until:
			print("[audit] Мост не отвечает")
			quit(2)
			return
		await create_timer(0.2).timeout
	var alerts: Dictionary = await _client.list_docs("alert")
	var n_aud := 0
	var n_other := 0
	for d in alerts.get("docs", []):
		var data: Dictionary = d["data"]
		var kind := str(data.get("kind", ""))
		if kind.begins_with("auditor_"):
			n_aud += 1
		else:
			n_other += 1
		print("[audit] alert ", d["id"], " ", kind, " ", str(data.get("msg", "")))
	var items: Dictionary = await _client.list_docs("item")
	var n_items := (items.get("docs", []) as Array).size()
	var sessions: Dictionary = await _client.list_docs("session")
	var open := 0
	var closed := 0
	var outcomes := {}
	for d in sessions.get("docs", []):
		var data: Dictionary = d["data"]
		if str(data.get("state")) == "closed":
			closed += 1
			var o := str(data.get("outcome"))
			outcomes[o] = int(outcomes.get(o, 0)) + 1
		else:
			open += 1
	if _args.has("dump"):
		await _dump(str(_args["dump"]), items, sessions)
	var parts: Array = []
	for k in outcomes:
		parts.append("%s:%d" % [k, outcomes[k]])
	print("[audit] alerts_auditor=%d alerts_other=%d items=%d sessions_open=%d sessions_closed=%d outcomes=%s" % [n_aud, n_other, n_items, open, closed, ",".join(parts)])
	var expected := int(_args.get("items", "-1"))
	quit(1 if expected >= 0 and expected != n_items else 0)


## `--dump=<файл>`: слепок для учений «выдернули питание» (tools/power_cut.sh): владельцы предметов, состояния сессий, документы узлов и их цели.
func _dump(path: String, items: Dictionary, sessions: Dictionary) -> void:
	var out := {"items": {}, "sessions": {}, "node": {}, "node_cfg": {}}
	for d in items.get("docs", []):
		out["items"][d["id"]] = str(d["data"].get("owner", ""))
	for d in sessions.get("docs", []):
		out["sessions"][d["id"]] = str(d["data"].get("state", ""))
	for t in ["node", "node_cfg"]:
		var r: Dictionary = await _client.list_docs(t)
		for d in r.get("docs", []):
			out[t][d["id"]] = {"ver": d["ver"], "data": d["data"]}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out))
