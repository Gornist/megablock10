class_name NodeLayout
extends RefCounted
## Геометрия узла Сети. Общая для сервера и клиента: сервер по ней ставит шарды, выход и маршруты ICE, клиент одевает её в 3D-ассеты
## (client/node_view.gd). Модули окружения лежат на сетке 2x2 м (assets/models/MANIFEST.md): комната 16x16 м — 8x8 ячеек, центры ячеек
## в нечётных координатах (x = -7…7, z = -13…1). Всё, что стоит «на ячейке» — спавн, хранилища шардов, порталы, колонны, — стоит в её
## центре; площадка выхода — на вершине между четырьмя ячейками (четыре помоста 2x2 вписывают круг r = 2). Стена стоит на краю ячейки
## и входит внутрь на WALL_THICKNESS.
## Колонны только для глаз: видимость ICE — расстояние и конус, препятствий она не учитывает (ice_brain.gd).

## Комната: x от -8 до 8, z от -14 до 2 (метры).
const ROOM_MIN := Vector2(-8.0, -14.0)
const ROOM_MAX := Vector2(8.0, 2.0)
## Ячейка модульного окружения и число ячеек по стороне комнаты.
const CELL := 2.0
const GRID := 8
## Стена внутрь ячейки (env/wall.glb).
const WALL_THICKNESS := 0.2
## Вход (спавн риг-а и аватара): центр ячейки (3; 6), лицом в -Z, в комнату.
const SPAWN := Vector3(-1, 0, -1)

## Шард лежит в хранилище (id объекта — NetConfig.PICKUP_ID); y = 1,0 — метка ShardSlot хранилища (props/vault_*.glb).
const SHARD_POS := Vector3(-1, 1.0, -9)
## Выход: площадка; «выйти чисто» можно, стоя на ней (по плоскости XZ). Вершина четырёх ячеек: помосты env/platform.glb в
## ячейках (3; 5) x (-1; 1). За южной стеной (z = 2) — две двери (EXIT_DOORS) и цифровой тоннель (EXIT_TUNNEL_SEGMENTS кольца по 2 м).
const EXIT_POS := Vector3(4, 0, 0)
const EXIT_RADIUS := 2.0
const EXIT_DOORS := [Vector3(3, 0, 1), Vector3(5, 0, 1)]
const EXIT_TUNNEL_SEGMENTS := 2
## Достаточная близость к объекту для взятия (м, по плоскости XZ; клиент берёт с запасом меньше).
const GRAB_REACH := 3.5

## Колонны (env/pillar.glb) — укрытия для глаз; центры ячеек.
const PILLARS := [Vector3(-3, 0, -5), Vector3(3, 0, -5), Vector3(-3, 0, -11), Vector3(1, 0, -11)]
## Стационарный датчик (props/sensor.glb): центр ячейки у западной стены, смотрит в комнату.
const SENSOR_POS := Vector3(-7, 0, -5)

## ICE: id и маршрут патруля (старт — первая точка, по маршруту ICE ходит по кругу). Маршруты идут по рёбрам ячеек (чётные координаты):
## центры ячеек, где стоят предметы, — в 1 м от них. Правила П1 (карточка 1б): маршрут не ближе MIN_VAULT_TO_ROUTE от любого хранилища (стоя у шарда
## игрок не на пути Стража) и не ближе 3 м от спавна и порталов; спавн и порталы вне конуса ICE на первой точке (ICE смотрит на вторую).
## ice_1 — «пояс» z = -4 между входом и хранилищами (старт у входа не виден: спавн у него за спиной), ice_2 — восточная колонна.
const ICE := [
	{"id": "ice_1", "waypoints": [Vector3(0, 0, -4), Vector3(6, 0, -4), Vector3(-4, 0, -4)]},
	{"id": "ice_2", "waypoints": [Vector3(6, 0, -6), Vector3(6, 0, -4), Vector3(6, 0, -8)]},
]

## Black ICE: есть только в узлах тира NIGHTMARE (GrayNode добавляет их по tier документа node).
const BLACK_ICE := [
	{"id": "black_1", "waypoints": [Vector3(2, 0, -6), Vector3(6, 0, -6)]},
]
## Хранилище (слот шарда) — не ближе этого (м, по плоскости XZ) к любой точке маршрута любого ICE, Soft или Black.
const MIN_VAULT_TO_ROUTE := 4.0

## Граф узлов (W1): общая комната у всех узлов, различаются тир, ICE, шарды и порталы. Шарды узла — по слотам (id объектов
## строит сервер), порталы-тоннели — по слотам площадок: у узла до трёх связей, i-я связь — слот i. Площадка портала r = 1,5 м
## целиком в комнате (центры ячеек второго ряда от стены и глубже).
const SHARD_SLOTS := [Vector3(-1, 1.0, -9), Vector3(-5, 1.0, -13), Vector3(5, 1.0, -13)]
const PORTAL_SLOTS := [Vector3(-5, 0, -1), Vector3(-5, 0, -9), Vector3(3, 0, -9)]
## Нетраннер у портала — в этом радиусе по плоскости XZ (сервер по нему начинает переход); приходит он на ARRIVE_DIST от своего портала.
const PORTAL_RADIUS := 1.5
const ARRIVE_DIST := 3.0
## К какой точке комнаты смотрит «внутрь» вход от портала.
const ROOM_CENTER := Vector3(0, 0, -6)

## Площадка у хранилища (К3): игрок, телепортировавшийся ближе VAULT_SNAP_RADIUS к хранилищу, встаёт в VAULT_PAD_DIST перед ним (с той стороны,
## куда смотрит модель) и разворачивается к нему: и панель взлома (0,65 м от глаз), и парящий шард в досягаемости сидя. Одна функция на сервер и клиент.
const VAULT_PAD_DIST := 0.85
const VAULT_SNAP_RADIUS := 1.6
## Дальше этого от хранилища сервер не начинает взлом (м, по плоскости): запас на плоскую сборку и неточность посадки.
const BREACH_REACH := 3.0

## Колода по умолчанию (демоны из data/daemons) и названия для деки.
const DEFAULT_DECK := ["ghost_1", "jitter_1"]
const DAEMON_NAMES := {"ghost_1": "Призрак", "jitter_1": "Дрожь", "extract_shard_1": "Извлечение"}
## Цепочки колоды по умолчанию (без Моста демоны приходят без цепочек): по ним работают заряд и взлом на стенде без Моста. Коды — из алфавита breach.json.
const DEFAULT_DECK_CELLS := {"ghost_1": ["1C", "BD"], "jitter_1": ["55", "E9"]}


static func in_room(p: Vector3) -> bool:
	return p.x >= ROOM_MIN.x and p.x <= ROOM_MAX.x and p.z >= ROOM_MIN.y and p.z <= ROOM_MAX.y


static func clamp_to_room(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, ROOM_MIN.x, ROOM_MAX.x), p.y, clampf(p.z, ROOM_MIN.y, ROOM_MAX.y))


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func on_exit_pad(p: Vector3) -> bool:
	return flat_distance(p, EXIT_POS) <= EXIT_RADIUS


## Центр ячейки (ix, iz): ix — слева направо, iz — от северной (-Z) стены к южной; на полу (y = 0).
static func cell_center(ix: int, iz: int) -> Vector3:
	return Vector3(ROOM_MIN.x + CELL * (ix + 0.5), 0.0, ROOM_MIN.y + CELL * (iz + 0.5))


## Стоит ли точка в центре ячейки (по плоскости XZ; допуск 1 мм).
static func is_cell_center(p: Vector3) -> bool:
	return _near_grid(p.x - ROOM_MIN.x, CELL * 0.5) and _near_grid(p.z - ROOM_MIN.y, CELL * 0.5)


## Стоит ли точка на вершине сетки (углы четырёх ячеек).
static func is_cell_vertex(p: Vector3) -> bool:
	return _near_grid(p.x - ROOM_MIN.x, 0.0) and _near_grid(p.z - ROOM_MIN.y, 0.0)


static func _near_grid(offset: float, shift: float) -> bool:
	var r := fposmod(offset - shift, CELL)
	return minf(r, CELL - r) < 0.001


## Расстояние от точки до ближайшей стены (до плоскости на краю ячейки, толщину стены не вычитаем).
static func wall_gap(p: Vector3) -> float:
	return minf(minf(p.x - ROOM_MIN.x, ROOM_MAX.x - p.x), minf(p.z - ROOM_MIN.y, ROOM_MAX.y - p.z))


## Центры четырёх ячеек под площадкой выхода.
static func exit_platform_cells() -> Array[Vector3]:
	var h := CELL * 0.5
	return [EXIT_POS + Vector3(-h, 0, -h), EXIT_POS + Vector3(h, 0, -h), EXIT_POS + Vector3(-h, 0, h), EXIT_POS + Vector3(h, 0, h)]


## Поворот вокруг Y, после которого локальный +Z (лицо предмета, MANIFEST) смотрит из `from` на `to`.
static func yaw_facing(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


## Поворот вокруг Y лицом к центру комнаты по ближайшему направлению сетки (0, ±90°, 180°): хранилища и датчик стоят вдоль стен.
static func cardinal_yaw(p: Vector3) -> float:
	var dx := ROOM_CENTER.x - p.x
	var dz := ROOM_CENTER.z - p.z
	if absf(dx) > absf(dz):
		return PI / 2.0 if dx > 0.0 else -PI / 2.0
	return 0.0 if dz > 0.0 else PI


## Площадка перед хранилищем в слоте slot (позиция шарда над ним, y не важен): с той стороны, куда смотрит модель (cardinal_yaw), на пол.
static func vault_pad(slot: Vector3) -> Vector3:
	var yaw := cardinal_yaw(Vector3(slot.x, 0.0, slot.z))
	return clamp_to_room(Vector3(slot.x + sin(yaw) * VAULT_PAD_DIST, 0.0, slot.z + cos(yaw) * VAULT_PAD_DIST))


## Точка телепорта p после привязки к площадке: ближайшее хранилище (из slots — позиции шардов) в пределах VAULT_SNAP_RADIUS даёт его площадку.
## Ответ {p, look}: look — Vector3 хранилища, к которому надо развернуть взгляд, или null, если привязки нет.
static func snap_to_vault_pad(p: Vector3, slots: Array) -> Dictionary:
	var best: Variant = null
	var best_d := VAULT_SNAP_RADIUS
	for s in slots:
		var d := flat_distance(p, s)
		if d <= best_d:
			best_d = d
			best = s
	if best == null:
		return {"p": p, "look": null}
	var slot: Vector3 = best
	var pad := vault_pad(slot)
	return {"p": Vector3(pad.x, p.y, pad.z), "look": Vector3(slot.x, 0.0, slot.z)}


## Где игрок появляется, пройдя через портал слота: на ARRIVE_DIST от него в сторону центра комнаты (вне радиуса портала —
## иначе переход сработал бы заново).
static func arrival_for_slot(slot: int) -> Vector3:
	if slot < 0 or slot >= PORTAL_SLOTS.size():
		return SPAWN
	var p: Vector3 = PORTAL_SLOTS[slot]
	var d := Vector3(ROOM_CENTER.x - p.x, 0.0, ROOM_CENTER.z - p.z).normalized()
	return clamp_to_room(p + d * ARRIVE_DIST)
