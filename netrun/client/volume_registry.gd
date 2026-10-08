class_name VolumeRegistry
extends RefCounted
## Реестр «объёмных» модулей (план «волюметрик»): какие объекты Сети рисуются облаком частиц (VolumeCloud) вместо сплошной модели.
## Задаётся ключом netrun.cfg `[render] volumetric`: "off" (по умолчанию) — нет облаков; "all" — все модули, у которых есть файл `.points`;
## список через запятую — только они ("ice,vault"). Имена модулей — произвольные слова клиента (vault, exit, portal, shard, ice, …).
## Файл точек лежит рядом с моделью: res://assets/models/props/vault.glb → vault.points. Нет файла — облака нет, модель остаётся прежней.

static var _all := false
static var _modules := PackedStringArray()


## Разобрать значение ключа volumetric.
static func configure(spec: String) -> void:
	var s := spec.strip_edges().to_lower()
	_all = s == "all"
	_modules = PackedStringArray()
	if s == "" or s == "off" or _all:
		return
	for m in s.split(",", false):
		_modules.append(m.strip_edges())


## Значение ключа → список модулей ([] — выкл., ["all"] — все). Чистая функция для RenderConfig и тестов.
static func parse_spec(spec: String) -> PackedStringArray:
	var s := spec.strip_edges().to_lower()
	if s == "" or s == "off":
		return PackedStringArray()
	if s == "all":
		return PackedStringArray(["all"])
	var out := PackedStringArray()
	for m in s.split(",", false):
		out.append(m.strip_edges())
	return out


## Рисуется ли модуль облаком (без учёта наличия файла).
static func is_enabled(module: String) -> bool:
	return _all or _modules.has(module)


## Путь файла точек рядом с моделью (.glb → .points).
static func points_path(model_path: String) -> String:
	return model_path.get_basename() + ".points"


## Облако для модуля или null: модуль выключен, файла точек нет или он битый. Узел добавляет вызывающий (родитель = узел модели).
static func spawn(module: String, model_path: String, color: Color, bounds: AABB) -> VolumeCloud:
	if not is_enabled(module):
		return null
	var pts := VolumeCloud.load_file(points_path(model_path))
	if pts.is_empty():
		return null
	var c := VolumeCloud.new()
	c.name = "Cloud_" + module
	c.setup(pts, color, bounds)
	return c
