class_name NodeLayout
extends RefCounted
## Геометрия серого узла node_07 (заглушка: комната с укрытиями, без ассетов). Общая для сервера и клиента:
## сервер по ней ставит шард, выход и маршруты ICE, клиент рисует то же самое.
## Укрытия только для глаз: видимость ICE — расстояние и конус, препятствий она не учитывает (ice_brain.gd).

## Комната: x от -8 до 8, z от -14 до 2 (метры). Вход (спавн риг-а) — начало координат.
const ROOM_MIN := Vector2(-8.0, -14.0)
const ROOM_MAX := Vector2(8.0, 2.0)
const SPAWN := Vector3(0, 0, 0)

## Шард лежит на постаменте (id объекта — NetConfig.PICKUP_ID).
const SHARD_POS := Vector3(0, 1.0, -10.0)
## Выход: площадка; «выйти чисто» можно, стоя на ней (по плоскости XZ).
const EXIT_POS := Vector3(5, 0, 1)
const EXIT_RADIUS := 2.0
## Достаточная близость к объекту для взятия (м, по плоскости XZ; клиент берёт с запасом меньше).
const GRAB_REACH := 3.5

## Укрытия: [центр, размер].
const COVERS := [
	[Vector3(-5, 0.75, -4), Vector3(2, 1.5, 0.5)],
	[Vector3(5, 0.75, -8), Vector3(2, 1.5, 0.5)],
	[Vector3(-3, 0.75, -9), Vector3(0.5, 1.5, 2)],
	[Vector3(3, 0.75, -3), Vector3(2, 1.5, 0.5)],
]

## ICE: id, старт и маршрут патруля.
const ICE := [
	{"id": "ice_1", "waypoints": [Vector3(-4, 0, -6), Vector3(4, 0, -6)]},
	{"id": "ice_2", "waypoints": [Vector3(6, 0, -12), Vector3(6, 0, -4)]},
]

## Black ICE: есть только в узлах тира NIGHTMARE (GrayNode добавляет их по tier документа node).
const BLACK_ICE := [
	{"id": "black_1", "waypoints": [Vector3(-6, 0, -12), Vector3(0, 0, -12), Vector3(6, 0, -12)]},
]

## Граф узлов (W1): общая комната у всех узлов, различаются тир, ICE, шарды и порталы. Шарды узла — по слотам (id объектов
## строит сервер), порталы-тоннели — по слотам площадок: у узла до трёх связей, i-я связь — слот i.
const SHARD_SLOTS := [Vector3(0, 1.0, -10.0), Vector3(-6, 1.0, -12.0), Vector3(6, 1.0, -10.0)]
const PORTAL_SLOTS := [Vector3(-6, 0, -1), Vector3(-7, 0, -6), Vector3(4, 0, -13)]
## Нетраннер у портала — в этом радиусе по плоскости XZ (сервер по нему начинает переход); приходит он на ARRIVE_DIST от своего портала.
const PORTAL_RADIUS := 1.5
const ARRIVE_DIST := 3.0
## К какой точке комнаты смотрит «внутрь» вход от портала.
const ROOM_CENTER := Vector3(0, 0, -6)

## Колода по умолчанию (демоны из data/daemons) и названия для деки.
const DEFAULT_DECK := ["ghost_1", "jitter_1"]
const DAEMON_NAMES := {"ghost_1": "Призрак", "jitter_1": "Дрожь", "extract_shard_1": "Извлечение"}


static func in_room(p: Vector3) -> bool:
	return p.x >= ROOM_MIN.x and p.x <= ROOM_MAX.x and p.z >= ROOM_MIN.y and p.z <= ROOM_MAX.y


static func clamp_to_room(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, ROOM_MIN.x, ROOM_MAX.x), p.y, clampf(p.z, ROOM_MIN.y, ROOM_MAX.y))


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func on_exit_pad(p: Vector3) -> bool:
	return flat_distance(p, EXIT_POS) <= EXIT_RADIUS


## Где игрок появляется, пройдя через портал слота: на ARRIVE_DIST от него в сторону центра комнаты (вне радиуса портала —
## иначе переход сработал бы заново).
static func arrival_for_slot(slot: int) -> Vector3:
	if slot < 0 or slot >= PORTAL_SLOTS.size():
		return SPAWN
	var p: Vector3 = PORTAL_SLOTS[slot]
	var d := Vector3(ROOM_CENTER.x - p.x, 0.0, ROOM_CENTER.z - p.z).normalized()
	return clamp_to_room(p + d * ARRIVE_DIST)
