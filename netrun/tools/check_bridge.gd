extends SceneTree
## Проверка документов настоящего Моста после живого прогона (live_run.sh): читает их по WebSocket и печатает `[check] ...`.
## `godot --headless --path netrun -s res://tools/check_bridge.gd -- --bridge=ws://127.0.0.1:7410/netrun/v1 --key=<ключ роли world>
##   --session=<сессия> --runner=<ключ игрока> --shard=<предмет> [--wait=60]`. Код 0 — всё сошлось, 1 — нет.
## Ждёт (до --wait секунд), пока сессия не закроется чисто, шард не окажется у игрока (outbox/phone), затем даёт аудитору
## Моста пройти и убеждается, что тревог (`alert`) нет.

var _client: BridgeClient
var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_client = BridgeClient.new(str(_args.get("bridge", "ws://127.0.0.1:7410/netrun/v1")), str(_args.get("key", "")), "live-check")
	_client.start()
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_client.poll()
	return false


func _finish(ok: bool, msg: String) -> void:
	print("[check] ", "OK: " if ok else "ПРОВАЛ: ", msg)
	quit(0 if ok else 1)


func _run() -> void:
	var wait_s := float(_args.get("wait", "60"))
	var until := Time.get_ticks_msec() + int(wait_s * 1000.0)
	var session := str(_args.get("session", ""))
	var runner := str(_args.get("runner", ""))
	var shard := str(_args.get("shard", ""))
	while not _client.is_ready():
		if Time.get_ticks_msec() > until:
			_finish(false, "Мост не отвечает")
			return
		await create_timer(0.2).timeout
	var last := ""
	var done := false
	while Time.get_ticks_msec() < until:
		var s: Dictionary = await _client.get_doc("session", session)
		var it: Dictionary = await _client.get_doc("item", shard)
		if s.get("ok", false) and it.get("ok", false):
			var sd: Dictionary = s["doc"]["data"]
			var owner := str(it["doc"]["data"].get("owner", ""))
			last = "сессия %s/%s, шард у %s" % [sd.get("state"), sd.get("outcome"), owner]
			var at_player := owner == "outbox:" + runner or owner == "phone:" + runner
			if sd.get("state") == "closed" and sd.get("outcome") == "clean" and at_player:
				done = true
				break
		await create_timer(0.5).timeout
	if not done:
		_finish(false, "не дождались исхода: " + last)
		return
	print("[check] ", last)
	# Все предметы деки (включая защищённого демона) — у игрока, ничего не осталось в деке или узле.
	var items: Dictionary = await _client.list_docs("item")
	var in_deck: Array = []
	var at_player := 0
	for d in items.get("docs", []):
		var owner := str(d["data"].get("owner", ""))
		if owner.begins_with("deck:") or (owner == "node:node_07" and d["data"].get("kind") != "SHARD"):
			in_deck.append(str(d["id"]))
		if owner == "outbox:" + runner or owner == "phone:" + runner:
			at_player += 1
	if not in_deck.is_empty():
		_finish(false, "предметы остались в деке или узле: %s" % str(in_deck))
		return
	print("[check] у игрока предметов: ", at_player)
	# Аудитор Моста (период — из seed, 2 с) проходит и не поднимает тревог.
	await create_timer(float(_args.get("audit", "5"))).timeout
	var alerts: Dictionary = await _client.list_docs("alert")
	if not alerts.get("ok", false) or not (alerts.get("docs", []) as Array).is_empty():
		_finish(false, "тревоги Моста: %s" % str(alerts.get("docs", alerts)))
		return
	var node: Dictionary = await _client.get_doc("node", "node_07")
	print("[check] узел: ", JSON.stringify(node.get("doc", {}).get("data", {})))
	_finish(true, "забег закрыт чисто, шард у игрока, тревог нет")
