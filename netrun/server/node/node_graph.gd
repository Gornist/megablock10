class_name NodeGraph
extends RefCounted
## Граф узлов Сети (W1) как данные: data/graph.json. Узлы (тир BASE/HARD/NIGHTMARE, число Soft ICE, шардов), связи-тоннели
## (симметричные: тоннель ходит в обе стороны, i-я связь узла — i-й слот портала в комнате, NodeLayout.PORTAL_SLOTS),
## узел входа по терминалу и числа настроек (переход, пополнение, остывание, локдаун). Чистые данные: без сцены и сети.
## Black ICE в графе не задаётся: он живёт только в узлах тира NIGHTMARE (GrayNode.apply_def).

const DEFAULT_PATH := "res://data/graph.json"
const TIERS: Array = ["BASE", "HARD", "NIGHTMARE"]
const TIER_BLACK := "NIGHTMARE"

## Числа по умолчанию; graph.json переопределяет любое (shard_refill_sec — по тирам, недостающие тиры — как в умолчании).
const DEFAULT_SETTINGS := {
	"tunnel_sec": 2.5,               # сколько длится цифровой тоннель между узлами
	"portal_dwell_sec": 1.0,         # сколько стоять в радиусе портала, чтобы он сработал
	"portal_radius": 1.5,            # м
	"portal_deny_repeat_sec": 3.0,   # как часто повторять отказ у закрытого портала (иначе — шквал сообщений)
	"shard_refill_sec": {"BASE": 600.0, "HARD": 900.0, "NIGHTMARE": 1200.0},  # через сколько после выноса шард узла появляется снова
	"refill_retry_sec": 30.0,        # если в Мосте для слота нет свободного шарда — повторить через
	"alert_per_trace": 0.3,          # тревога узла растёт, когда trace игрока достиг уровня TRACE
	"alert_per_eject": 0.6,          # ... и когда ICE выбросил или поймал игрока
	"alert_cool_sec": 300.0,         # за сколько тревога остывает от 1 до 0
	"alert_boost": 0.5,              # при полной тревоге зрение ICE и скорость его внимания выше на эту долю
	"vault_requires_open": "auto",   # взять шард можно, только открыв хранилище взломом: true / false, "auto" — включено, когда у узла графа есть Мост (GrayNode.vault_requires_open)
	"vault_open_sec": 60.0,          # на сколько секунд взлом открывает хранилище (run.breach: open_s, 1..600)
	"trap_trace": {"BASE": 5.0, "HARD": 8.0, "NIGHTMARE": 12.0},  # сколько trace даёт ловушка во взломе (мёртвая клетка или порченый код), по тиру узла
	"alert_per_fail": 0.3,           # тревога узла растёт, когда взлом закончился провалом (FAIL)
	"lockdown_sec": 600.0,           # локдаун узла после выброса; без Моста держит сам сервер мира, с Мостом — lockdown_until узла
}

var nodes: Dictionary = {}          # id -> {title, tier, ice, shards, links: Array[String]}
var entries: Dictionary = {}        # терминал -> id узла входа
var default_entry := ""
var settings: Dictionary = {}
var load_error := ""


static func from_dict(d: Dictionary) -> NodeGraph:
	var g := NodeGraph.new()
	g.settings = DEFAULT_SETTINGS.duplicate(true)
	var s: Variant = d.get("settings")
	if s is Dictionary:
		for k in s:
			if g.settings.get(k) is Dictionary and s[k] is Dictionary:
				(g.settings[k] as Dictionary).merge(s[k], true)
			else:
				g.settings[k] = s[k]
	var raw: Variant = d.get("nodes")
	if raw is Dictionary:
		for id in raw:
			var n: Dictionary = raw[id] if raw[id] is Dictionary else {}
			var links: Array = []
			for l in n.get("links", []):
				links.append(str(l))
			g.nodes[str(id)] = {
				"title": str(n.get("title", id)),
				"tier": str(n.get("tier", "BASE")),
				"ice": int(n.get("ice", 1)),
				"shards": int(n.get("shards", 1)),
				"links": links,
				"tutorial": bool(n.get("tutorial", false)),
				"ice_settings": n["ice_settings"] if n.get("ice_settings") is Dictionary else {},
				"signs": n["signs"] if n.get("signs") is Array else [],
			}
	var e: Variant = d.get("entries")
	if e is Dictionary:
		for t in e:
			g.entries[str(t)] = str(e[t])
	g.default_entry = str(d.get("default_entry", ""))
	return g


static func load_file(path: String = DEFAULT_PATH) -> NodeGraph:
	if not FileAccess.file_exists(path):
		var g := NodeGraph.new()
		g.load_error = "файла нет: " + path
		return g
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		var g := NodeGraph.new()
		g.load_error = "не разобрать JSON: " + path
		return g
	return from_dict(parsed)


## Что не так с графом (пусто — всё хорошо). Общие правила; число узлов (10–12) проверяет тест на настоящем graph.json.
func errors() -> Array[String]:
	var out: Array[String] = []
	if load_error != "":
		out.append(load_error)
		return out
	if nodes.is_empty():
		out.append("узлов нет")
	for id in nodes:
		var n: Dictionary = nodes[id]
		if not (n["tier"] in TIERS):
			out.append("%s: неизвестный тир «%s»" % [id, n["tier"]])
		if int(n["ice"]) < 0 or int(n["ice"]) > NodeLayout.ICE.size():
			out.append("%s: ICE %d, допустимо 0…%d" % [id, n["ice"], NodeLayout.ICE.size()])
		if int(n["shards"]) < 1 or int(n["shards"]) > NodeLayout.SHARD_SLOTS.size():
			out.append("%s: шардов %d, допустимо 1…%d" % [id, n["shards"], NodeLayout.SHARD_SLOTS.size()])
		var links: Array = n["links"]
		if links.size() > NodeLayout.PORTAL_SLOTS.size():
			out.append("%s: связей %d, слотов порталов %d" % [id, links.size(), NodeLayout.PORTAL_SLOTS.size()])
		if links.is_empty() and not bool(n.get("tutorial", false)):
			out.append("%s: нет связей" % id)
		if bool(n.get("tutorial", false)):
			if not links.is_empty():
				out.append("%s: учебный узел без связей с графом" % id)
			if n["tier"] == TIER_BLACK:
				out.append("%s: в учебном узле нет Black ICE" % id)
		for l in links:
			if l == id:
				out.append("%s: связь с самим собой" % id)
			elif not nodes.has(l):
				out.append("%s: связь с неизвестным узлом %s" % [id, l])
			elif not (id in (nodes[l] as Dictionary)["links"]):
				out.append("%s -> %s: тоннель не симметричен" % [id, l])
		if links.size() != _unique(links).size():
			out.append("%s: повтор связи" % id)
	if not nodes.is_empty() and not _connected():
		out.append("граф не связный")
	if not nodes.has(default_entry):
		out.append("default_entry «%s» — не узел" % default_entry)
	for t in entries:
		if not nodes.has(entries[t]):
			out.append("вход терминала %s: неизвестный узел %s" % [t, entries[t]])
	for id in [default_entry] + entries.values():
		if nodes.has(id) and nodes[id]["tier"] == TIER_BLACK:
			out.append("вход в узле %s (NIGHTMARE): с Black ICE не начинают" % id)
		if is_tutorial(id):
			out.append("вход терминала в учебном узле %s: его выбирает Мост по tutorial_done" % id)
	return out


## Учебный узел (первый вход новичка): без связей, вне связности графа, не вход по умолчанию.
func is_tutorial(id: String) -> bool:
	return bool((nodes.get(id, {}) as Dictionary).get("tutorial", false))


func has_node(id: String) -> bool:
	return nodes.has(id)


func tier_of(id: String) -> String:
	return str((nodes.get(id, {}) as Dictionary).get("tier", ""))


func title_of(id: String) -> String:
	return str((nodes.get(id, {}) as Dictionary).get("title", id))


func is_linked(from: String, to: String) -> bool:
	return nodes.has(from) and to in (nodes[from] as Dictionary)["links"]


## Слот портала в узле from, ведущего в узел to (-1 — связи нет).
func slot_to(from: String, to: String) -> int:
	if not nodes.has(from):
		return -1
	return (nodes[from] as Dictionary)["links"].find(to)


## Узел входа для терминала: из данных, иначе узел по умолчанию.
func entry_for(terminal: String) -> String:
	return str(entries.get(terminal, default_entry))


## Через сколько секунд после выноса шард узла появляется снова.
func refill_sec(tier: String) -> float:
	var m: Variant = settings.get("shard_refill_sec")
	if m is Dictionary:
		return float((m as Dictionary).get(tier, 0.0))
	return float(m) if (m is float or m is int) else 0.0


func _unique(a: Array) -> Array:
	var out: Array = []
	for x in a:
		if not (x in out):
			out.append(x)
	return out


func _connected() -> bool:
	var main: Array = nodes.keys().filter(func(id): return not is_tutorial(id))
	if main.is_empty():
		return true
	var start: String = main[0]
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var cur: String = queue.pop_back()
		for l in (nodes[cur] as Dictionary)["links"]:
			if nodes.has(l) and not seen.has(l):
				seen[l] = true
				queue.append(l)
	return seen.size() == main.size()
