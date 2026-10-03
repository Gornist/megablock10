class_name NodeView
extends Node3D
## Узел глазами клиента: комната из модулей окружения и предметы на местах игры, всё из готовых 3D-ассетов (NodeAssets).
## Раскладка — shared/node_layout.gd (та же, по которой сервер ставит шарды, порталы и выход). Что показывать, решает сервер:
## тир узла, шарды и порталы приходят событием node, охота и уровень trace — снимком state. Здесь только сборка и переключение моделей.
## Повторяющиеся модули (пол 64 плитки, стены, колонны, помосты, кольца тоннеля) — по одному MultiMesh на модуль: комната в десятке
## вызовов отрисовки вместо сотни. Предметы (хранилища, порталы, кресло, датчик) — обычные экземпляры: их по десятку, и они переключаются.
## Камеру не трогает никогда: двигается только по воле игрока.

## Метка ShardSlot хранилища (props/vault_*.glb) — центр шарда над основанием.
const VAULT_SLOT_Y := 1.0
## Мёртвая дека лежит на полу: origin приподнят (MANIFEST: +0,035 м).
const DEAD_DECK_LIFT := 0.035
const SENSOR_SWEEP_RAD := 0.6
const SENSOR_SWEEP_HZ := 0.12
const MODULES := ["floor", "wall", "corner", "pillar", "platform", "doorway", "lockdown_gate", "tunnel_ring"]

## Тир узла, по которому выбраны файлы окружения (BASE, если сервер тир не назвал).
var tier := ""
## Выходы закрыты (уровень trace LOCKDOWN): вместо дверей — lockdown_gate. Сервер сам выход не закрывает: это сигнал среды.
var exit_locked := false
## За игроком идёт охота Black ICE: порталы закрыты.
var hunted := false

var _room: Node3D
var _props: Node3D
var _furniture: Node3D
var _sensor: Node3D
var _counts: Dictionary = {}
var _doorways: Array[Node3D] = []
var _gates: Array[Node3D] = []
var _vaults: Dictionary = {}     # id слота -> {open, closed}
var _portals: Array[Dictionary] = []  # {to, open, ok, locked}
var _closed_to: Dictionary = {}  # узлы, которые сервер отказался открыть (локдаун): портал в них закрыт, пока не придёт новое событие node
var _seat: Node3D
var _t := 0.0


func _init() -> void:
	name = "NodeView"
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)
	_furniture = Node3D.new()
	_furniture.name = "Furniture"
	add_child(_furniture)
	# Кресло узла там, где игрок появляется; датчик у стены (свёрнут к центру комнаты), его голова качается.
	_seat = _place(_furniture, NodeAssets.prop_path("seat"), NodeLayout.SPAWN, 0.0)
	_sensor = _place(_furniture, NodeAssets.prop_path("sensor"), NodeLayout.SENSOR_POS, NodeLayout.cardinal_yaw(NodeLayout.SENSOR_POS))
	set_tier("BASE")


func _process(delta: float) -> void:
	_t += delta
	if _sensor != null:
		_sensor.rotation.y = NodeLayout.cardinal_yaw(NodeLayout.SENSOR_POS) + sin(_t * TAU * SENSOR_SWEEP_HZ) * SENSOR_SWEEP_RAD


# ---------------------------------------------------------------- комната

## Комната под тир узла. Тот же тир — ничего не пересобираем.
func set_tier(new_tier: String) -> void:
	var t := NodeAssets.normalize_tier(new_tier)
	if t == tier and _room != null:
		return
	tier = t
	_discard(_room)
	_room = Node3D.new()
	_room.name = "Room"
	add_child(_room)
	_doorways.clear()
	_gates.clear()
	_counts.clear()
	var xforms := _room_transforms()
	for module in MODULES:
		var list: Array = xforms[module]
		_counts[module] = list.size()
		var made := _add_multi(_room, NodeAssets.env_path(module, tier), module, list)
		if module == "doorway":
			_doorways = made
		elif module == "lockdown_gate":
			_gates = made
	_apply_exit()


## Сколько экземпляров каждого модуля в комнате (для проверки сетки).
func module_counts() -> Dictionary:
	return _counts


## Выход открыт (двери) или заперт (ворота lockdown_gate с решёткой Bars_Closed).
func set_exit_locked(locked: bool) -> void:
	exit_locked = locked
	_apply_exit()


func _apply_exit() -> void:
	for n in _doorways:
		n.visible = not exit_locked
	for n in _gates:
		n.visible = exit_locked


## Преобразования модулей: пол на каждую ячейку, стены по периметру (поворот вокруг Y: стена по умолчанию — на северном краю -Z),
## углы с колонной, двери выхода в южной стене (там же ворота — они показываются вместо дверей), помосты под площадкой выхода,
## колонны-укрытия и кольца цифрового тоннеля за южной стеной.
func _room_transforms() -> Dictionary:
	var out := {}
	for module in MODULES:
		out[module] = []
	var last := NodeLayout.GRID - 1
	for iz in NodeLayout.GRID:
		for ix in NodeLayout.GRID:
			var c := NodeLayout.cell_center(ix, iz)
			out["floor"].append(Transform3D(Basis.IDENTITY, c))
			var north := iz == 0
			var south := iz == last
			var west := ix == 0
			var east := ix == last
			if (north or south) and (west or east):
				var corner_yaw := 0.0                                # северо-запад: стены -Z и -X
				if north and east:
					corner_yaw = 3.0 * PI / 2.0
				elif south and east:
					corner_yaw = PI
				elif south and west:
					corner_yaw = PI / 2.0
				out["corner"].append(Transform3D(Basis(Vector3.UP, corner_yaw), c))
			elif north or south or west or east:
				var wall_yaw := 0.0 if north else (PI if south else (PI / 2.0 if west else 3.0 * PI / 2.0))
				var t := Transform3D(Basis(Vector3.UP, wall_yaw), c)
				if south and _is_exit_door(c):
					out["doorway"].append(t)
					out["lockdown_gate"].append(t)
				else:
					out["wall"].append(t)
	for c in NodeLayout.exit_platform_cells():
		out["platform"].append(Transform3D(Basis.IDENTITY, c))
	for p in NodeLayout.PILLARS:
		out["pillar"].append(Transform3D(Basis.IDENTITY, p))
	for k in NodeLayout.EXIT_TUNNEL_SEGMENTS:
		out["tunnel_ring"].append(Transform3D(Basis.IDENTITY, Vector3(NodeLayout.EXIT_POS.x, 0.0, NodeLayout.ROOM_MAX.y + NodeLayout.CELL * (k + 0.5))))
	return out


func _is_exit_door(cell: Vector3) -> bool:
	for d in NodeLayout.EXIT_DOORS:
		if NodeLayout.flat_distance(cell, d) < 0.01:
			return true
	return false


## По одному MultiMeshInstance3D на меш модели (у ворот их два: Frame и Bars_Closed).
func _add_multi(parent: Node3D, path: String, label: String, xforms: Array) -> Array[Node3D]:
	var made: Array[Node3D] = []
	if xforms.is_empty():
		return made
	for part in NodeAssets.mesh_parts(path):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = xforms.size()
		mm.mesh = part["mesh"]
		for i in xforms.size():
			mm.set_instance_transform(i, (xforms[i] as Transform3D) * (part["xform"] as Transform3D))
		var mi := MultiMeshInstance3D.new()
		mi.name = "%s_%s" % [label, part["name"]]
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("asset", path)
		parent.add_child(mi)
		made.append(mi)
	return made


# ---------------------------------------------------------------- предметы узла

func _place(parent: Node3D, path: String, pos: Vector3, yaw: float) -> Node3D:
	var n := NodeAssets.instance(path)
	n.position = pos
	n.rotation.y = yaw
	parent.add_child(n)
	return n


## Убрать узел из дерева и освободить сразу (queue_free оставил бы его в сцене до конца кадра). Звать только вне обхода этих узлов.
func _discard(n: Node) -> void:
	if n == null:
		return
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	n.free()


func seat_node() -> Node3D:
	return _seat


## Хранилища под слоты шардов узла [{id, p: [x, y, z], ready}]: готовый слот — открытое хранилище, пустой (шард вынесен, ждёт
## пополнения) — закрытое. Лицом к центру комнаты по сетке; шард лежит в метке ShardSlot на 1 м над основанием.
func set_vaults(shards: Array) -> void:
	for id in _vaults:
		for n in (_vaults[id] as Dictionary).values():
			_discard(n)
	_vaults.clear()
	for sh in shards:
		var p: Array = sh["p"]
		var base := Vector3(float(p[0]), maxf(float(p[1]) - VAULT_SLOT_Y, 0.0), float(p[2]))
		var yaw := NodeLayout.cardinal_yaw(base)
		var open := _place(_props, NodeAssets.prop_path("vault_open"), base, yaw)
		var closed := _place(_props, NodeAssets.prop_path("vault_closed"), base, yaw)
		_vaults[str(sh["id"])] = {"open": open, "closed": closed}
		set_vault_ready(str(sh["id"]), bool(sh.get("ready", true)))


func set_vault_ready(id: String, has_shard: bool) -> void:
	var v: Dictionary = _vaults.get(id, {})
	if v.is_empty():
		return
	(v["open"] as Node3D).visible = has_shard
	(v["closed"] as Node3D).visible = not has_shard


func vault_open(id: String) -> bool:
	var v: Dictionary = _vaults.get(id, {})
	return not v.is_empty() and (v["open"] as Node3D).visible


## Порталы узла [{to, p: [x, z], open}]: площадка и арка лицом к центру комнаты. Закрыты (portal_locked), если узел назначения
## в локдауне (open = false), если сервер отказал в переходе (close_portal) или за игроком идёт охота Black ICE (set_hunted).
func set_portals(portals: Array) -> void:
	for pt in _portals:
		_discard(pt["ok"])
		_discard(pt["locked"])
	_portals.clear()
	_closed_to.clear()
	for pt in portals:
		var p: Array = pt["p"]
		var pos := Vector3(float(p[0]), 0.0, float(p[1]))
		var yaw := NodeLayout.yaw_facing(pos, NodeLayout.ROOM_CENTER)
		_portals.append({
			"to": str(pt["to"]), "open": bool(pt.get("open", true)),
			"ok": _place(_props, NodeAssets.prop_path("portal"), pos, yaw),
			"locked": _place(_props, NodeAssets.prop_path("portal_locked"), pos, yaw),
		})
	_apply_portals()


func set_hunted(on: bool) -> void:
	if on == hunted:
		return
	hunted = on
	_apply_portals()


## Сервер не открыл портал в узел `to` (локдаун): рисуем его закрытым.
func close_portal(to: String) -> void:
	_closed_to[to] = true
	_apply_portals()


func _apply_portals() -> void:
	for pt in _portals:
		var locked: bool = hunted or not bool(pt["open"]) or _closed_to.has(pt["to"])
		(pt["ok"] as Node3D).visible = not locked
		(pt["locked"] as Node3D).visible = locked


func portal_locked(i: int) -> bool:
	return (_portals[i]["locked"] as Node3D).visible


func portal_node(i: int) -> Node3D:
	return _portals[i]["ok"]


## Мёртвые деки в узле [[x, z], ...] (флэтлайн оставляет деку в узле, её может подобрать другой).
func set_dead_decks(spots: Array) -> void:
	for c in _props.get_children():
		if str(c.get_meta("asset", "")) == NodeAssets.prop_path("dead_deck"):
			_discard(c)
	for i in spots.size():
		var s: Array = spots[i]
		_place(_props, NodeAssets.prop_path("dead_deck"), Vector3(float(s[0]), DEAD_DECK_LIFT, float(s[1])), float(i) * 1.3)


# ---------------------------------------------------------------- отладка и бюджет

## Пути подключённых и видимых ассетов под корнем (без повторов).
static func collect_assets(root: Node) -> Array:
	var out: Array = []
	_collect_assets(root, out)
	return out


func used_assets() -> Array:
	return collect_assets(self)


static func _collect_assets(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Node3D and not (c as Node3D).visible:
			continue
		if c.has_meta("asset") and not out.has(c.get_meta("asset")):
			out.append(c.get_meta("asset"))
		_collect_assets(c, out)


## id меша -> {mesh, n}: меш держим, чтобы его id не заняли заново
static var _mesh_tris: Dictionary = {}


static func _mesh_triangles(mesh: Mesh) -> int:
	var key := mesh.get_instance_id()
	if _mesh_tris.has(key):
		return _mesh_tris[key]["n"]
	var total := 0
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var corners := 0  # вершины треугольников: по индексам, а без них — по вершинам
		if arrays[Mesh.ARRAY_INDEX] != null:
			corners = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		else:
			corners = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		total += int(corners / 3.0)
	_mesh_tris[key] = {"mesh": mesh, "n": total}
	return total


## Треугольники видимых мешей под корнем: MultiMesh считается по числу экземпляров.
static func count_triangles(root: Node) -> int:
	if root is Node3D and not (root as Node3D).visible:
		return 0
	var total := 0
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		total += _mesh_triangles((root as MeshInstance3D).mesh)
	elif root is MultiMeshInstance3D and (root as MultiMeshInstance3D).multimesh != null:
		var mm := (root as MultiMeshInstance3D).multimesh
		if mm.mesh != null:
			total += _mesh_triangles(mm.mesh) * mm.instance_count
	for c in root.get_children():
		total += count_triangles(c)
	return total


## Оценка вызовов отрисовки: поверхность видимого меша — вызов, MultiMesh — вызов на поверхность независимо от числа экземпляров.
## Точное число в кадре даёт Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME (только в окне, не в тестах без экрана).
static func count_draw_calls(root: Node) -> int:
	if root is Node3D and not (root as Node3D).visible:
		return 0
	var total := 0
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		total += (root as MeshInstance3D).mesh.get_surface_count()
	elif root is MultiMeshInstance3D and (root as MultiMeshInstance3D).multimesh != null and (root as MultiMeshInstance3D).multimesh.mesh != null:
		total += (root as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
	for c in root.get_children():
		total += count_draw_calls(c)
	return total
