class_name VolumeRegistry
extends RefCounted
## Реестр «объёмных» модулей (план «волюметрик»): какие объекты Сети рисуются облаком частиц (VolumeCloud) вместо сплошной модели.
## Задаётся ключом netrun.cfg `[render] volumetric`: "off" (по умолчанию) — нет облаков; "all" — все модули, у которых есть файл `.points`;
## список через запятую — только они ("ice,vault"). Имена модулей — произвольные слова клиента (vault, exit, portal, shard, ice, …).
## Файл точек лежит рядом с моделью: res://assets/models/props/vault.glb → vault.points (его пишет генератор Blender). Нет файла — точки берутся с поверхности
## самой модели на лету (VolumeSampler, число точек — SAMPLE_COUNTS): так облако можно мерить на очках до генератора; файл, когда появится, главнее.

## Сколько точек сэмплировать по модулю, когда файла `.points` нет (бюджет плана: хранилище ≈ 1,5k, выход ≈ 1k, портал ≈ 0,8k, шард ≈ 0,3k).
const SAMPLE_COUNTS := {"vault": 1500, "exit": 1000, "portal": 800, "shard": 300}
const SAMPLE_DEFAULT := 800
const SAMPLE_SEED := 20261013

static var _all := false
static var _modules := PackedStringArray()
## Сэмплированные точки по пути модели: сэмплируем один раз, все экземпляры (порталы, хранилища) берут тот же массив.
static var _sampled: Dictionary = {}


## Разобрать значение ключа volumetric.
static func configure(spec: String) -> void:
	_sampled.clear()
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
	var box := bounds
	if pts.is_empty():
		var key := "%s|%s" % [module, model_path]
		if not _sampled.has(key):
			_sampled[key] = VolumeSampler.sample_parts(NodeAssets.mesh_parts(model_path), int(SAMPLE_COUNTS.get(module, SAMPLE_DEFAULT)), SAMPLE_SEED)
		pts = _sampled[key]
		if pts.is_empty():
			return null
		if box.size == Vector3.ZERO:
			box = VolumeSampler.bounds_of(pts)
	var c := VolumeCloud.new()
	c.name = "Cloud_" + module
	c.setup(pts, color, box)
	return c
