class_name CloudLightPlan
extends RefCounted
## Невидимые источники света облака узла (решение владельца 18.10: частицы видны только в освещении). Чистые функции без сцены: по раскладке
## строится список для AssetMaterials.set_cloud_lights — [{"p": Vector3 мир, "r": радиус м, "s": сила, "c": Color (только у угрозы)}].
## Где ставить — данные узла (здесь); радиус спада, цвет света и отклик частиц — у Blender (AssetMaterials / шейдер облака).
##
## Раскладка задала `lights` — берём только их. Иначе набор по умолчанию, в порядке важности (лишнее сверх CLOUD_LIGHTS_MAX отбрасывается с хвоста):
## вход, выход, хранилища, порталы, угрозы (Маяки, Датчики, Стражи, логово — красные), центр комнаты (проход между зонами).

const MAX := 12
const Y := 1.0                       ## высота источника, м
const R_SPAWN := 4.0
const R_EXIT := 3.0
const R_VAULT := 3.0
const R_PORTAL := 3.0
const R_THREAT := 3.0
const R_CENTER := 4.0
## Красный свет угрозы ICE (цвет по палитре Blender: «красный — у угрозы ICE/ворот»).
const THREAT_COLOR := Color(1.0, 0.25, 0.3)


## Источники света узла с раскладкой (не legacy). Раскладка null или legacy — for_legacy().
static func build(layout: LayoutData) -> Array:
	if layout == null or layout.is_legacy() or not layout.error.is_empty():
		return for_legacy()
	if not layout.lights.is_empty():
		var out: Array = []
		for l: Dictionary in layout.lights:
			out.append(_light(l["pos"], float(l["r"]), float(l["s"]), bool(l["threat"])))
		return out.slice(0, MAX)
	var lights: Array = []
	lights.append(_light(layout.spawn, R_SPAWN))
	lights.append(_light(layout.exit_pos, R_EXIT))
	for v: Dictionary in layout.vaults:
		lights.append(_light(v["slot"], R_VAULT))
	for p: Vector3 in layout.portals:
		if p != Vector3.INF:
			lights.append(_light(p, R_PORTAL))
	for b: Dictionary in layout.beacons:
		lights.append(_light(NodeGrid.center(b["cell"]), R_THREAT, 1.0, true))
	for s: Dictionary in layout.sensors:
		var cells: Array = s["cells"]
		if not cells.is_empty():
			lights.append(_light(NodeGrid.center(cells[int(cells.size() * 0.5)]), maxf(R_THREAT, cells.size() * 0.5), 1.0, true))
	for g: Dictionary in layout.sentries:
		var route: Array = g["route"]
		if not route.is_empty():
			lights.append(_light(NodeGrid.center(route[0]["cell"]), R_THREAT, 1.0, true))
	if not layout.lair.is_empty():
		lights.append(_light(NodeGrid.center(layout.lair["home"]), R_THREAT, 1.0, true))
	lights.append(_light(layout.room_center(), R_CENTER))
	return lights.slice(0, MAX)


## Прежняя комната (layout == null или legacy): вход, выход и шард-заглушка.
static func for_legacy() -> Array:
	return [
		_light(NodeLayout.SPAWN, R_SPAWN),
		_light(NodeLayout.EXIT_POS, R_EXIT),
		_light(NodeLayout.SHARD_POS, R_VAULT),
	]


static func _light(p: Vector3, r: float, s: float = 1.0, threat: bool = false) -> Dictionary:
	var out := {"p": Vector3(p.x, Y, p.z), "r": r, "s": s}
	if threat:
		out["c"] = THREAT_COLOR   # без "c" облако берёт свой бирюзово-белый по умолчанию
	return out
