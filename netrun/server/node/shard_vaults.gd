class_name ShardVaults
extends RefCounted
## Шарды и хранилища узла на сервере мира: слоты, кто что взял, открытость взломом, вынос и пополнение. Вынесено из GrayNode
## (рефакторинг, поведение то же). Держит ссылку на узел (как NodeAlarm и LayoutDevices): сессии, часы, Мост, события и запись узла
## остаются там — здесь только состояние слотов и их правила. Сигналы (shard_depleted, shard_refilled, vault_closed, shard_taken)
## по-прежнему идут через node.event. Публичные имена GrayNode (vault_state, open_vault, settle_shards …) — тонкие делегаты сюда.
## Статические shard_id / shard_meta / vault_meta / shard_encrypted остались в GrayNode (их зовут снаружи как GrayNode.*).

var node: GrayNode
var items: Dictionary = {}           # id объекта -> id предмета в Мосте
var item_meta: Dictionary = {}       # id предмета узла -> {tier, enc}: что показывать на шарде (из документа Моста)
var vault_open: Dictionary = {}      # id слота -> сессия, для которой хранилище открыто взломом (K3); нужно, только если включён vault_requires_open
var vault_open_until: Dictionary = {} # id слота -> время узла, когда открытость кончается (нет записи — без срока)
var slot_pos: Dictionary = {}        # id объекта (слот шарда узла) -> позиция
var taken_by: Dictionary = {}        # сессия -> [id слотов этого узла, которые она взяла]
var refill_at: Dictionary = {}       # id пустого слота -> когда пробовать пополнить (время узла)
var refill_busy: Dictionary = {}     # id слота -> идёт запрос шарда в Мосте


func _init(owner_node: GrayNode) -> void:
	node = owner_node


## Слоты шардов: одиночный узел — один объект pickup_01 на постаменте, узел графа — по числу шардов в def.
func build_slots() -> void:
	if node.node_def.is_empty():
		slot_pos[NetConfig.PICKUP_ID] = NodeLayout.SHARD_POS
		node.net.place_object(NetConfig.PICKUP_ID, NodeLayout.SHARD_POS)
		return
	var wanted := int(node.node_def.get("shards", 1))
	if wanted > node.layout.vaults.size():
		push_warning("[node] %s: шардов %d, а хранилищ в раскладке «%s» %d — лишние не создаём" % [node.node_id, wanted, node.layout.name, node.layout.vaults.size()])
	for k in mini(wanted, node.layout.vaults.size()):   # первые хранилища раскладки; остальные пустые (слотов нет)
		var id := GrayNode.shard_id(node.node_id, k)
		var pos: Vector3 = node.layout.vaults[k]["slot"]
		slot_pos[id] = pos
		node.net.add_object(id, pos)


## Слоты, которые к рестарту ждали пополнения: id слота -> сколько секунд осталось (refill — {слот: срок, мс Unix}).
## Без этого пополнение после рестарта начиналось бы сразу, а не по таймеру узла.
func restore_refill_slots(saved_world: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var saved: Variant = saved_world.get("refill")
	if not saved is Dictionary:
		return out
	var now_ms := Time.get_unix_time_from_system() * 1000.0
	for sid in saved:
		if slot_pos.has(sid):
			out[sid] = maxf((float(saved[sid]) - now_ms) / 1000.0, 0.0)
	return out


## Разбор снимка Моста, часть про слоты: шарды, которые игроки уже несут (held), и свободные предметы узла (node_items) занимают слоты,
## слоты с ещё не подошедшим пополнением остаются пустыми, прочие пустеют сразу. active — активные сессии узла.
func restore(node_items: Array[String], held: Array, active: Array[String], saved_world: Dictionary) -> void:
	var free_slots: Array = slot_pos.keys()
	var pending := restore_refill_slots(saved_world)  # слоты, чьё пополнение ещё не подошло: остаются пустыми
	for sid in pending:
		free_slots.erase(sid)
	# Шард, который игрок уже несёт, остаётся у него: клиент второй раз его не возьмёт, выход вернёт его по moves.
	for h in held:
		if h["by"] in active and not free_slots.is_empty():
			var sid: String = free_slots.pop_front()
			items[sid] = h["item"]
			node.net.restore_holder(sid, h["by"])
			taken_by[h["by"]] = taken_by.get(h["by"], []) + [sid]
	for item in node_items:
		if free_slots.is_empty():
			break
		items[free_slots.pop_front()] = item
		node._given.erase(item)
	if not free_slots.is_empty() and not node.is_tutorial():
		if node.node_def.is_empty():
			push_warning("[gray-node] в Мосте нет шарда в узле %s: добыча останется только игровой" % node.node_id)
		else:
			for sid in free_slots:  # слот без шарда пуст, пока в Мосте не появится свободный (пополнение)
				deplete(sid, 0.0)
	for sid in pending:
		deplete(sid, float(pending[sid]))


func slot_ids() -> Array:
	return slot_pos.keys()


func has_slot(slot: String) -> bool:
	return slot_pos.has(slot)


## Вид хранилища слота для сессии: empty — шарда нет (вынесен, ждёт пополнения); closed — шард внутри, взять нельзя;
## open — можно взять. Пока флаг `vault_requires_open` выключен (по умолчанию), лежащий шард открыт всем; К3 включает флаг, и
## хранилище открывается только взломом (open_vault) и только для сессии, которая его взломала.
func vault_state(slot: String, session: String = "") -> String:
	if node.net.holder_of(slot) != "":
		return GrayNode.VAULT_EMPTY
	if node.vault_requires_open() and not (session != "" and vault_open.get(slot) == session):
		return GrayNode.VAULT_CLOSED
	return GrayNode.VAULT_OPEN


## Хранилище слота открыто для сессии (взлом удался): взять шард может только она. sec > 0 — на столько секунд (vault_open_sec), 0 — без срока.
## Шлёт обновление слотов всем игрокам узла.
func open_vault(slot: String, session: String, sec: float = 0.0) -> void:
	if not slot_pos.has(slot):
		return
	vault_open[slot] = session
	if sec > 0.0:
		vault_open_until[slot] = node._now + sec
	else:
		vault_open_until.erase(slot)
	push_shards()


## Хранилище закрылось снова (срок vault_open_sec вышел, шард взят или слот опустел).
func close_vault(slot: String) -> void:
	vault_open_until.erase(slot)
	if vault_open.erase(slot):
		push_shards()


## Закрыть всё, что было открыто для сессии (игрок ушёл из узла или кончил забег).
func close_vaults_of(session: String) -> void:
	for slot in vault_open.keys():
		if vault_open[slot] == session:
			close_vault(slot)


func expire_vaults() -> void:
	if vault_open_until.is_empty():
		return
	for slot in vault_open_until.keys():
		if node._now >= float(vault_open_until[slot]):
			close_vault(slot)
			node.event.emit({"kind": "vault_closed", "id": slot})


## Слот, в котором лежит предмет Моста item ("" — ни в одном).
func slot_of_item(item: String) -> String:
	for slot in items:
		if items[slot] == item:
			return slot
	return ""


## Сколько секунд слоту ждать пополнения (0 — не ждёт).
func refill_left(slot: String) -> int:
	return ceili(maxf(float(refill_at.get(slot, node._now)) - node._now, 0.0)) if refill_at.has(slot) else 0


## Доступ сессии к хранилищу для панели взлома: access — empty (ждёт пополнения, left — секунд) | open (можно брать) | busy (взламывает другой) |
## cooldown (это хранилище остывает для неё — у каждого своё, left — секунд) | ok (можно начинать).
func vault_access(slot: String, session: String) -> Dictionary:
	if node.net.holder_of(slot) != "":
		return {"access": "empty", "left": refill_left(slot)}
	if vault_state(slot, session) == GrayNode.VAULT_OPEN:
		return {"access": "open"}
	if node.breach != null and node.breach.is_busy(slot, session):
		return {"access": "busy"}
	var ds: DaemonSession = node._sessions.get(session)
	if ds != null and not node.is_tutorial():
		var left: float = node.breach.cooldown_left(ds, slot)
		if left > 0.0:
			return {"access": "cooldown", "left": ceili(left)}
	return {"access": "ok"}


## Мёртвые деки в узле для клиента: [[x, z]] рядом со слотами, где лежит демон мёртвой деки (на 0,8 м к центру комнаты от хранилища).
func dead_decks() -> Array:
	var out: Array = []
	for id in slot_pos:
		var meta: Dictionary = item_meta.get(items.get(id, ""), {})
		if bool(meta.get("dead", false)):
			var p: Vector3 = slot_pos[id]
			var to_center := Vector2(-p.x, -p.z).normalized() * 0.8
			out.append([p.x + to_center.x, p.z + to_center.y])
	return out


## Слоты шардов для клиента: [{id, p, ready, vault, tier?, enc?, kind?, dead?}] для сессии. ready — предмет лежит; vault — empty | closed | open
## (vault_state); tier, enc и kind — признаки лежащего предмета (из Моста; учебный узел и работа без Моста их не знают).
func shard_view(session: String = "") -> Array:
	var out: Array = []
	for id in slot_pos:
		var p: Vector3 = slot_pos[id]
		var st := vault_state(id, session)
		var e := {"id": id, "p": [p.x, p.y, p.z], "ready": st != GrayNode.VAULT_EMPTY, "vault": st, "dead": false}
		e.merge(vault_access(id, session))
		var meta: Dictionary = item_meta.get(items.get(id, ""), {})
		if st != GrayNode.VAULT_EMPTY and not meta.is_empty():
			e["tier"] = meta["tier"]
			e["enc"] = meta["enc"]
			e["kind"] = meta.get("kind", "shard")
			if meta.has("dead"):
				e["dead"] = true
		out.append(e)
	return out


## Сколько слотов шардов ждут пополнения.
func empty_slots() -> int:
	return refill_at.size()


## Сроки пополнения слотов для node.data.world.refill: {слот: срок, мс Unix}.
func refill_deadlines() -> Dictionary:
	var refill: Dictionary = {}
	var now_ms := Time.get_unix_time_from_system() * 1000.0
	for sid in refill_at:
		refill[sid] = int(now_ms + maxf(float(refill_at[sid]) - node._now, 0.0) * 1000.0)
	return refill


## Шард взят (NetServer уже отдал объект): слот записан за сессией, открытость кончилась вместе с шардом.
func on_taken(object_id: String, session: String) -> void:
	taken_by[session] = taken_by.get(session, []) + [object_id]
	vault_open.erase(object_id)
	vault_open_until.erase(object_id)


## Шард слота ушёл навсегда (на телефон или в другой узел) — слот пуст, пополнится через delay секунд (если в Мосте найдётся шард).
func deplete(id: String, delay: float) -> void:
	node.net.lock_object(id)
	items.erase(id)
	vault_open.erase(id)
	vault_open_until.erase(id)
	refill_at[id] = node._now + delay
	node.event.emit({"kind": "shard_depleted", "id": id})


## Забег игрока закончился (GraphWorld зовёт все узлы): слоты, где он взял шард, пустеют — кроме случая, когда добыча осталась
## в этом же узле (выброс/флэтлайн/обрыв: предмет вернулся в узел, слот снова с шардом).
func settle_shards(session: String, end_node: String, loot: String) -> void:
	var ids: Array = taken_by.get(session, [])
	taken_by.erase(session)
	if ids.is_empty() or node.is_tutorial():  # заглушка учебного узла лежит снова — пополнять нечего
		return
	var delay := float((node.settings["shard_refill_sec"] as Dictionary).get(node.tier(), 0.0))
	for id in ids:
		if loot == "node" and end_node == node.node_id and not node.is_given_away(str(items.get(id, "")), session):
			continue   # добыча осталась в узле — кроме отданной другому игроку: она в узел не вернётся
		deplete(id, delay)
	push_shards()
	node._write_node_state()


## Автопополнение стоит, пока узел в локдауне и пока в нём идёт охота Black ICE (docs/netrun.md, «Открытые вопросы», п. 2): сроки слотов
## не сбрасываются, слот оживает на ближайшем тике после конца локдауна/охоты. Сколько слотов — решает граф: сверх его числа шардов не будет.
func is_refill_paused() -> bool:
	return node.is_locked_down() or node.is_hunt_active()


func tick_refill() -> void:
	if refill_at.is_empty() or is_refill_paused():
		return
	for id in refill_at.keys():
		if node._now >= float(refill_at[id]) and not refill_busy.has(id):
			refill(id)


## Пополнение слота: с Мостом нужен свободный шард `node:<узел>` (Мост выпускает шарды; сервер мира их не создаёт), без Моста
## слот просто оживает. Нет свободного — повтор через refill_retry_sec.
func refill(id: String) -> void:
	refill_busy[id] = true
	var item := ""
	if node.bridge != null:
		item = await free_shard_item()
		if item.is_empty() or item in items.values():
			refill_busy.erase(id)
			if refill_at.has(id):
				refill_at[id] = node._now + float(node.settings["refill_retry_sec"])
			return
	refill_busy.erase(id)
	if not refill_at.has(id) or is_refill_paused():
		return  # пока шард искали в Мосте, узел закрылся или началась охота: слот остаётся пустым, повторит тик
	refill_at.erase(id)
	if not item.is_empty():
		items[id] = item
		node._given.erase(item)   # шард лежит в узле: прежняя отдача (A -> B -> узел) к нему больше не относится
	node.net.unlock_object(id)
	node.event.emit({"kind": "shard_refilled", "id": id, "item": item})
	push_shards()
	node._write_node_state()


## Свободный предмет узла в Мосте — шард или демон: owner node:<узел>, не привязанный к слоту. "" — нет. Демоны («мёртвая дека», наполнение
## мастера) — такие же свободные предметы, их достаёт EXTRACT_DAEMON (протокол, 6.9); порядок общий, по возрастанию id.
func free_shard_item() -> String:
	if not node.synced or not node.bridge.is_ready():
		return ""
	@warning_ignore("redundant_await")
	var r: Dictionary = await node.bridge.list_docs(BridgeApi.T_ITEM)
	if not r.get("ok", false):
		return ""
	var ids: Array[String] = []
	for d in r.get("docs", []):
		var data: Dictionary = d.get("data", {})
		if (data.get("kind") == "SHARD" or data.get("kind") == "DAEMON") and data.get("owner") == "node:" + node.node_id \
				and not (str(d["id"]) in items.values()):
			ids.append(str(d["id"]))
			item_meta[str(d["id"])] = GrayNode.vault_meta(data)
	ids.sort()
	return ids[0] if not ids.is_empty() else ""


func push_shards() -> void:
	for session in node._live_sessions():   # вид хранилищ у каждого свой: «открыто для тебя»
		node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {"kind": WorldMsg.EV_SHARDS, "shards": shard_view(session)}))
