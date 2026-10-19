class_name NodeDeck
extends RefCounted
## Дека и обмен грузом узла на сервере мира: что дека показывает игроку (`ev deck`), загрузка деки, груза и остывания из Моста,
## перезарядки в снимке и учёт отданного другому (К5б). Вынесено из GrayNode (рефакторинг, поведение то же). Держит ссылку на узел
## (как ShardVaults и NodeAlarm): сессии, Мост, сеть и демоны остаются там — здесь только состояние обмена и правила деки.
## Публичные имена GrayNode (deck_view, cd_entry, refresh_deck, can_exchange, note_given …) — тонкие делегаты сюда.
## Статические is_working_item / deck_from_items / loot_from_items / finish_moves остались в GrayNode (их зовут снаружи как GrayNode.*).
## Общий счётчик незавершённых отдач (`_takes_inflight`, begin_inflight / end_inflight) остаётся в узле: его разделяет весь граф.

var node: GrayNode
var given: Dictionary = {}           # id предмета, отданного игроком другому (К5б) -> сессия, у которой он теперь ("" — ушёл на телефон); слот отданного шарда не вернуть на постамент


func _init(owner_node: GrayNode) -> void:
	node = owner_node


## Что дека показывает про сессию (событие `ev deck`): RAM и занятое ею, рабочие демоны (имя, эффект, тир, цепочка), груз и эдди.
func deck_view(ds: DaemonSession) -> Dictionary:
	var daemons := node.daemons
	var rows: Array = []
	var used := 0
	for id in ds.deck:
		var def := daemons.get_def(id)
		var meta: Dictionary = ds.deck_meta.get(id, {})
		var cells: Array = (meta.get("cells", []) as Array).map(func(c: Variant) -> String: return str(c))
		used += cells.size()
		var row := {"id": id, "name": daemons.display_name(id, NodeLayout.DAEMON_NAMES.get(id, id)), "effect": def.effect if def != null else "",
			"tier": def.tier if def != null else 1, "cells": cells, "prot": bool(meta.get("prot", false)), "loaded": true, "chargeable": daemons.is_chargeable(id)}
		if def != null and def.unsupported_reason != "":
			row["unsupported"] = def.unsupported_reason
		rows.append(row)
	return {"kind": WorldMsg.EV_DECK, "ram": ds.ram, "ram_default": ds.ram_default, "used": used, "daemons": rows,
		"loot": ds.loot_view, "eddies": ds.loot_eddies}


func push_deck(session: String) -> void:
	var ds: DaemonSession = node._sessions.get(session)
	if ds != null:
		node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, deck_view(ds)))


## Строка перезарядок в снимке: к {id, name, left} добавлены st (ready | charged | cooldown | active | unsupported) и until (время сервера, когда
## состояние кончится; нет у ready и unsupported). active — действует эффект (GHOST, JITTER) и важнее перезарядки, которая идёт параллельно.
func cd_entry(ds: DaemonSession, id: String, now: float) -> Dictionary:
	var daemons := node.daemons
	var def := daemons.get_def(id)
	var left := ds.cooldown_left(id, now)
	var entry := {"id": id, "name": daemons.display_name(id, NodeLayout.DAEMON_NAMES.get(id, id)), "left": left, "st": "ready"}
	if def != null and def.unsupported_reason != "":
		entry["st"] = "unsupported"
		return entry
	var act := ds.active_left(def.effect, now) if def != null else 0.0
	if act > 0.0:
		entry["st"] = "active"
		entry["until"] = snappedf(now + act, 0.001)
	elif left > 0.0:
		entry["st"] = "cooldown"
		entry["until"] = snappedf(now + left, 0.001)
	elif ds.is_charged(id):
		entry["st"] = "charged"
	return entry


## Дека и груз из Моста (предметы deck:<сессия>), RAM и эдди из документа сессии; в конце — событие `ev deck` игроку.
func load_deck(session: String) -> void:
	var bridge := node.bridge
	if bridge == null or not bridge.is_ready():
		return
	@warning_ignore("redundant_await")
	var r: Dictionary = await bridge.list_docs(BridgeApi.T_ITEM)
	var ds: DaemonSession = node._sessions.get(session)
	if ds == null or not r.get("ok", false):
		return
	var docs: Array = r.get("docs", [])
	# Сессия нужна до деления на рабочих и груз (`loaded`, RAM): документ предметов один без неё не скажет, кто рабочий.
	@warning_ignore("redundant_await")
	var sr: Dictionary = await bridge.get_doc(BridgeApi.T_SESSION, session)
	if node._sessions.get(session) != ds:
		return   # сессия ушла, пока ждали Мост
	var sdata: Dictionary = {}
	if sr.get("ok", false):
		sdata = (sr["doc"] as Dictionary).get("data", {})
	var ids: Array[String] = []
	var meta := {}
	for e in GrayNode.deck_from_items(docs, session, sdata):
		var def := node.daemons.add_item_daemon(e["id"], e["daemon"])
		if def != null:
			ids.append(def.id)
			meta[def.id] = {"cells": e["daemon"].get("cells", []), "prot": e["protected"]}
			if def.unsupported_reason != "":
				print("[gray-node] ", session, ": демон ", def.display_name, " (", def.effect, ") не работает в Сети: ", def.unsupported_reason)
	if not ids.is_empty():
		ds.deck = ids
		ds.deck_meta = meta
	ds.loot_view = GrayNode.loot_from_items(docs, session, sdata)
	if not sdata.is_empty():
		var ram := int(sdata.get("ram", 0))
		if ram > 0:   # нет поля (сессия до К2): остаётся значение по умолчанию с пометкой
			ds.ram = ram
			ds.ram_default = false
		ds.loot_eddies = int(sdata.get("loot_eddies", 0))
		ds.runner_key = str(sdata.get("runner", ""))
	await load_cooldown(session, ds)
	if node._sessions.get(session) == ds:
		push_deck(session)


## Остывание узлов для игрока из документа runner (breach_cooldown: узел -> мс Unix): по ключу игрока из сессии. Нет документа — остывания нет.
func load_cooldown(session: String, ds: DaemonSession) -> void:
	if ds.runner_key.is_empty():
		return
	@warning_ignore("redundant_await")
	var r: Dictionary = await node.bridge.list_docs(BridgeApi.T_RUNNER)
	if node._sessions.get(session) != ds or not r.get("ok", false):
		return
	for d in r.get("docs", []):
		var data: Dictionary = d.get("data", {})
		if str(data.get("key", "")) == ds.runner_key and data.get("breach_cooldown") is Dictionary:
			var cds: Dictionary = {}
			for k in data["breach_cooldown"]:
				cds[str(k)] = int(data["breach_cooldown"][k])
			ds.breach_cooldown = cds
			node._push_shards()   # панель взлома показывает «ОСТЫВАЕТ»


## Можно ли менять груз сессии: она в узле, аватар на месте и забег не закрывается (выход, флэтлайн, охота за исходом).
func can_exchange(session: String) -> bool:
	return node._sessions.has(session) and node.net != null and node.net.has_avatar(session) and not node._finishing.has(session) and not node._exiting.has(session)


## Предмет отдан: теперь он у сессии `holder` ("" — на телефоне контакта). Запоминаем, чтобы слот шарда, откуда его взяли, не показал его
## снова. Вернулся к тому, кто его брал (A -> B -> A), — settle_shards снова видит его у него и слот не пустеет зря.
func note_given(item: String, holder: String = "") -> void:
	given[item] = holder


## Предмет отдан кому-то, кроме `session` (у неё его нет): слот, откуда она его взяла, после её выхода не вернуть на постамент.
func is_given_away(item: String, session: String) -> bool:
	return given.has(item) and str(given[item]) != session
