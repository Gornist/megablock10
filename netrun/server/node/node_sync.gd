class_name NodeSync
extends RefCounted
## Связь узла с Мостом: снимок при старте, восстановление после рестарта сервера мира и запись состояния узла (node.data.world).
## Вынесено из GrayNode (рефакторинг, поведение то же). Держит ссылку на узел (как ShardVaults, NodeAlarm и NodeDeck): сессии, сеть,
## тревога и слоты остаются там — здесь только порядок разбора снимка и цикл записи.
## Публичные имена GrayNode (apply_snapshot, recover, put_field, _write_node_state …) — тонкие делегаты сюда.
## Статический GrayNode.held_items и константа SYNC_TYPES остались в узле: их зовут снаружи.

var _node: GrayNode
var _node_write_busy := false    # запись node.data.world уже идёт: новые вызовы только взводят повтор
var _node_write_again := false


func _init(owner_node: GrayNode) -> void:
	_node = owner_node


## Снимок Моста: ждём связи, подписываемся, восстанавливаем (после рестарта сервера мира здесь же приходит прошлый забег).
func sync_from_bridge() -> void:
	var bridge := _node.bridge
	if bridge == null:
		return
	while not bridge.is_ready():
		await _node.get_tree().create_timer(0.1).timeout
		if not _node.is_inside_tree():
			return
	@warning_ignore("redundant_await")
	var snap: Dictionary = await bridge.subscribe(GrayNode.SYNC_TYPES)
	if not _node.is_inside_tree():
		return
	if not snap.get("ok", false):
		push_warning("[gray-node] подписка на Мост не удалась: %s" % BridgeApi.err_code(snap))
		return
	apply_snapshot(snap.get("docs", []))


## Снимок Моста принят: восстановление и первая запись состояния узла.
func apply_snapshot(docs: Array) -> void:
	recover(docs)
	_node.synced = true
	for session in _node.outcome.hunt_written.keys():
		_node.outcome._sync_hunt(session)  # охота прошлого процесса не продолжается: снять её отметку в Мосте
	_node._write_node_state()


## Разбор снимка: узел (локдаун), шард, активные сессии этого узла. Публичный — для тестов.
func recover(docs: Array) -> void:
	var node_id := _node.node_id
	var node_items: Array[String] = []   # свободные предметы узла: шарды и демоны (хранилище с демоном — К8)
	var deck_docs: Array = []            # предметы deck:<сессия> — кто из них добыча, решает session.loaded (после разбора всех сессий)
	var active_data: Dictionary = {}     # активные сессии этого узла: id -> data документа
	var active: Array[String] = []
	var opened: Array = []               # [{session, item, until}] хранилища, открытые взломами активных сессий (session.data.opened, пишет Мост)
	var flatlined: Dictionary = {}  # сессия -> disconnect: сервер упал, пока ждал мастера (пометка world.finish)
	var saved_world: Dictionary = {}     # node.data.world прошлого процесса: тревога и сроки пополнения слотов
	for d in docs:
		var data: Dictionary = d.get("data", {})
		match str(d.get("type", "")):
			BridgeApi.T_NODE:
				if d["id"] == node_id:
					_node.lockdown_until = int(data.get("lockdown_until", 0))
					if data.get("world") is Dictionary:
						saved_world = data["world"]
			BridgeApi.T_SESSION:
				if data.get("state") == "active" and _node._session_location(data) == node_id:
					var w: Variant = data.get("world")
					if w is Dictionary and (w as Dictionary).get("finish") == "flatline":
						flatlined[str(d["id"])] = bool((w as Dictionary).get("disconnect", false))
					else:
						active.append(str(d["id"]))
						active_data[str(d["id"])] = data
						for o in data.get("opened", []):
							if o is Dictionary and str(o.get("node", node_id)) == node_id:
								opened.append({"session": str(d["id"]), "item": str(o.get("item", "")), "until": int(o.get("until", 0))})
						if w is Dictionary and (w as Dictionary).get("hunt") == true:
							_node.outcome.hunt_written[str(d["id"])] = true  # отметка прошлого процесса: его охоты нет, apply_snapshot её снимет
			BridgeApi.T_ITEM:
				if data.get("kind") != "SHARD" and data.get("kind") != "DAEMON":
					continue
				var owner := str(data.get("owner", ""))
				if owner == "node:" + node_id:
					node_items.append(str(d["id"]))
					_node.shards.item_meta[str(d["id"])] = _node.vault_meta(data)
				elif owner.begins_with("deck:"):
					deck_docs.append(d)
	var held := GrayNode.held_items(deck_docs, active_data, node_id, _node.node_def.is_empty())   # [{item, by}] добыча, которую игроки несут из этого узла
	if _node.is_tutorial():
		node_items.clear()  # шард учебного узла — заглушка: предметов Моста к нему не привязываем
		held.clear()
	node_items.sort()
	_node.alarm_state.restore(saved_world)
	_node.shards.restore(node_items, held, active, saved_world)   # слоты: добыча игроков, свободные предметы узла, ожидающие пополнения
	# Хранилища, открытые взломом до рестарта, остаются открытыми взломщику до срока (Мост помнит их в session.opened).
	var now_ms := Time.get_unix_time_from_system() * 1000.0
	for o in opened:
		var slot := _node.slot_of_item(o["item"])
		if slot != "" and float(o["until"]) > now_ms:
			_node.open_vault(slot, o["session"], (float(o["until"]) - now_ms) / 1000.0)
	for s in active:
		_node.recovered_sessions.append(s)
		_node._exiting[s] = true  # аватара не было: avatar_removed не придёт, а в графе забег закрывает только узел с этой меткой
		_node.net.set_node(s, node_id)
		_node.net.expect_session(s)
	# Флэтлайн, начатый прошлым процессом: окна возврата нет, ждём мастера дальше и закрываем забег тем же исходом.
	for s in flatlined:
		_node.recovered_flatlines.append(s)
		_node._finishing[s] = true
		print("[gray-node] сессия ", s, ": флэтлайн из прошлого процесса, продолжаем ожидание мастера")
		_node._finish_in_bridge({"session": s, "reason": ExitLogic.REASON_FLATLINE, "under_hunt": false, "deck_burned": false,
			"disconnect": flatlined[s]})
	print("[gray-node] снимок Моста (", node_id, "): активных сессий ", active.size(), ", шард ", ",".join(_node.shards.items.values()) if not _node.shards.items.is_empty() else "—", ", локдаун до ", _node.lockdown_until)


## Где сессия сейчас: последняя запись сервера мира (world.node), иначе узел из документа Моста (куда её приняли).
func session_location(data: Dictionary) -> String:
	var w: Variant = data.get("world")
	if w is Dictionary and (w as Dictionary).has("node"):
		return str((w as Dictionary)["node"])
	return str(data.get("node", _node.node_id))


func on_doc_changed(doc: Dictionary, deleted: bool) -> void:
	if deleted or doc.get("type") != BridgeApi.T_NODE or doc.get("id") != _node.node_id:
		return
	_node.lockdown_until = int((doc.get("data", {}) as Dictionary).get("lockdown_until", 0))


## node.data.world = {up, players}: что видит мастер. Мост — источник правды, остальные поля узла не трогаем.
func write_node_state() -> void:
	if _node.bridge == null or not _node.synced:
		return
	if _node_write_busy:
		_node_write_again = true
		return
	_node_write_busy = true
	while true:
		_node_write_again = false
		var world := {"up": true, "players": _node._live_sessions().size()}
		if _node.is_graph_node():
			world["alert"] = snappedf(_node.alert, 0.01)           # прежняя шкала 0…1 (читатели прошлой версии)
			world["alarm"] = snappedf(_node.alarm, 1.0)            # Т3b: шкала 0–100 и уровень 0–4 рядом со старым полем
			world["alert_level"] = _node.alarm_level
			world["slots_empty"] = _node.shards.empty_slots()
			world["alert_at"] = int(Time.get_unix_time_from_system() * 1000.0)
			world["refill"] = _node.shards.refill_deadlines()
		var ok := await put_field(BridgeApi.T_NODE, _node.node_id, "world", world)
		if ok:
			_node.node_writes += 1
		if not _node_write_again or not _node.is_inside_tree():
			break
	_node_write_busy = false


## Чтение-правка-запись одного поля data документа с повтором при version_conflict. false — не вышло (документа нет, отказ).
func put_field(type: String, id: String, key: String, value: Variant) -> bool:
	for attempt in 3:
		@warning_ignore("redundant_await")
		var g: Dictionary = await _node.bridge.get_doc(type, id)
		if not g.get("ok", false):
			return false
		var cur: Dictionary = g["doc"]
		var data: Dictionary = (cur.get("data", {}) as Dictionary).duplicate(true)
		data[key] = value
		@warning_ignore("redundant_await")
		var r: Dictionary = await _node.bridge.put_doc(type, id, int(cur["ver"]), data)
		if r.get("ok", false):
			return true
		if BridgeApi.err_code(r) != "version_conflict":
			push_warning("[gray-node] put %s/%s: %s" % [type, id, BridgeApi.err_code(r)])
			return false
	return false
