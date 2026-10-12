class_name RenderConfig
extends RefCounted
## Настройки сглаживания и разрешения клиента без пересборки: секция [render] того же файла netrun.cfg, что читает NetConfig
## (тот же поиск по `NetConfig.default_paths()`, берётся первый прочитанный). Владелец подбирает на очках руками (`tools/pico.sh provision`).
## Нет файла или секции — значения по умолчанию; поле неверно — по умолчанию для этого поля и строка в `warnings`
## (клиент пишет в журнал `render.warn`), клиент не падает.
##
## [render]
## msaa = 2                  ; 3D-сглаживание: 2 (по умолчанию — принято владельцем 12.10: держит 90 Гц), 4 или 0 (выкл., только для сравнения)
##                           ; (замеры Pico 4, bench entry: msaa 2 = 90 fps / GPU 9,7 мс; msaa 4 = 73 fps / 13,0 мс — не влезает в 11,1 мс)
## layers = "behind"        ; панели (дека, взлом, итог) слоями композитора OpenXR: "behind" (по умолчанию), "on" или "off"
##                           ; (чёткий текст и линии; нужна поддержка слоёв рантаймом). "behind" — слой позади сцены с вырезом в альфе, руки и луч
##                           ; наводки рисуются поверх панели и объектов; "on" — слой поверх сцены (руки и луч пропадают за панелью); "off" — панели 3D-плоскостями
## foveation = 0             ; фовеация (OpenXR): 0 выкл. (по умолчанию), 1 низкая, 2 средняя, 3 высокая; при msaa > 0 принудительно 0
##                           ; (MSAA с фовеацией на Adreno 650 даёт пустой экран)
##
## Удалённые ключи aa, fringe, scale, foveation_dynamic (тупики замеров 08–12.10) в старых файлах игнорируются с предупреждением.
## perf = "off"             ; счётчик кадра: "on" — раз в 5 с строка `[perf]` (FPS, среднее / максимум времени кадра, GPU-время) в журнал клиента и logcat;
##                           ; "diag" — то же плюс XrDiag: через 8 с строка `[xr-diag]` (фовеация, VRS, MSAA, размеры цели на уровне OpenXR) и PNG кадра вида в user://
## volumetric = "off"       ; объекты Сети облаком частиц (VolumeRegistry): "off" (по умолчанию), "all" или модули через запятую ("ice,vault"); нужен файл `.points` у модели
## bench = ""               ; воспроизводимый замер (BenchRun): имя пресета EyePresets (entry, north, south, vault_w, …) — через 5 с риг встаёт в его позу, 3 окна по 10 с,
##                           ; строка `[bench] ИТОГ` с медианой и min/max окон по fps / времени кадра / GPU; голову во время замера не вертеть; пусто — выкл.
## probe = ""               ; синтетическая нагрузка (LoadProbe): "quads=N,px=P,mode=blend|a2c|opaque|point" — N квадов по P пикселей, приклеенных к голове; "sweep" — серия вариантов за один запуск (ProbeSweep); пусто — выкл.

const SECTION := "render"
const KEYS := ["msaa", "layers", "foveation", "perf", "volumetric", "bench", "probe"]
## Ключи, удалённые рефактором (docs/netrun-refactor-plan.md): в старых netrun.cfg на очках встречаются, значения не читаем.
const LEGACY_KEYS := ["aa", "fringe", "scale", "foveation_dynamic"]
const VOLUMETRIC_DEFAULT := "off"
const PERF_VALUES := ["on", "off", "diag"]
const PERF_DEFAULT := "off"
const LAYERS_VALUES := ["on", "off", "behind"]
const LAYERS_DEFAULT := "behind"
const MSAA_DEFAULT := 2
const FOVEATION_DEFAULT := 0
const FOVEATION_MAX := 3

var msaa: int = MSAA_DEFAULT
## Панели слоями композитора OpenXR: "behind" (по умолчанию) | "on" | "off".
var layers: String = LAYERS_DEFAULT
## Счётчик кадра (FramePerf): "on" | "off".
var perf: String = PERF_DEFAULT
## Объёмные модули (VolumeRegistry): "off" | "all" | список через запятую.
var volumetric: String = VOLUMETRIC_DEFAULT
## Пресет воспроизводимого замера (BenchRun) или "" — выкл.
var bench: String = ""
## Спецификация синтетической нагрузки (LoadProbe) или "" — выкл.
var probe: String = ""
var foveation: int = FOVEATION_DEFAULT
## Откуда прочитан файл ("" — файла или секции не было).
var file_path: String = ""
## Что в файле не так (по строке на поле).
var warnings: Array[String] = []


## Первый прочитанный файл из paths; нет файла — значения по умолчанию без предупреждений (файл необязателен).
static func load_file(paths: PackedStringArray = NetConfig.default_paths()) -> RenderConfig:
	for p in paths:
		if not FileAccess.file_exists(p):
			continue
		var cf := ConfigFile.new()
		var err := cf.load(p)
		if err != OK:
			var broken := RenderConfig.new()
			broken.warnings.append("файл %s не читается (%s): значения по умолчанию" % [p, error_string(err)])
			return broken
		var c := from_config(cf)
		c.file_path = p
		return c
	return RenderConfig.new()


static func from_config(cfg: ConfigFile) -> RenderConfig:
	var c := RenderConfig.new()
	if not cfg.has_section(SECTION):
		return c
	for key in cfg.get_section_keys(SECTION):
		var v: Variant = cfg.get_value(SECTION, key)
		match key:
			"msaa":
				var n: Variant = _int(v)
				if n != null and (n == 0 or n == 2 or n == 4):
					c.msaa = n
				else:
					c.warnings.append("msaa: допустимо 0, 2 или 4, получено «%s» — оставлено %d" % [v, c.msaa])
			"layers":
				if v is String and (v as String).to_lower() in LAYERS_VALUES:
					c.layers = (v as String).to_lower()
				else:
					c.warnings.append("layers: допустимо «on», «off» или «behind», получено «%s» — оставлено «%s»" % [v, c.layers])
			"perf":
				if v is String and (v as String).to_lower() in PERF_VALUES:
					c.perf = (v as String).to_lower()
				else:
					c.warnings.append("perf: допустимо «on», «off» или «diag», получено «%s» — оставлено «%s»" % [v, c.perf])
			"bench":
				var b := str(v).strip_edges().to_lower()
				if b == "" or EyePresets.names().has(b):
					c.bench = b
				else:
					c.warnings.append("bench: нет пресета «%s» (есть: %s) — замер выключен" % [b, ", ".join(EyePresets.names())])
			"probe":
				var spec := LoadProbe.parse(str(v))
				c.probe = str(v).strip_edges().to_lower() if spec["on"] else ""
				for w in spec["warnings"]:
					c.warnings.append(w)
			"volumetric":
				if v is String:
					c.volumetric = (v as String).strip_edges().to_lower()
				else:
					c.warnings.append("volumetric: нужна строка («off», «all» или модули через запятую), получено «%s» — оставлено «%s»" % [v, c.volumetric])
			"foveation":
				var n: Variant = _int(v)
				if n != null and n >= 0 and n <= FOVEATION_MAX:
					c.foveation = n
				else:
					c.warnings.append("foveation: нужно целое 0…%d, получено «%s» — оставлено %d" % [FOVEATION_MAX, v, c.foveation])
			_:
				if key in LEGACY_KEYS:
					c.warnings.append("ключ «%s» удалён (тупик замеров 08–12.10): игнорируется" % key)
				else:
					c.warnings.append("неизвестный ключ «%s»: пропущен" % key)
	# MSAA с фовеацией на Adreno 650 даёт пустой экран (замер 08.10): фовеация гасится, если включено MSAA
	if c.msaa > 0 and c.foveation > 0:
		c.warnings.append("foveation=%d при msaa=%d даёт пустой экран на Pico 4: foveation принудительно 0" % [c.foveation, c.msaa])
		c.foveation = 0
	return c


## Целое из int, целого float (2.0) или строки «2»; иначе null.
static func _int(v: Variant) -> Variant:
	var n: Variant = _number(v)
	if n == null or not is_equal_approx(float(n), roundf(float(n))):
		return null
	return int(roundf(float(n)))


static func _number(v: Variant) -> Variant:
	var x := NAN
	if v is float or v is int:
		x = float(v)
	elif v is String and (v as String).is_valid_float():
		x = (v as String).to_float()
	if is_finite(x):
		return x
	return null


## Режим Viewport.msaa_3d по числу из конфига (чистый маппинг, без сцены).
static func msaa_mode(n: int) -> Viewport.MSAA:
	match n:
		2:
			return Viewport.MSAA_2X
		4:
			return Viewport.MSAA_4X
	return Viewport.MSAA_DISABLED


## Панели слоями композитора включены в конфиге? (чистый маппинг, без сцены)
static func layers_enabled(s: String) -> bool:
	return s == "on" or s == "behind"


## Счётчик кадра включён в конфиге?
static func perf_enabled(s: String) -> bool:
	return s == "on" or s == "diag"


## Диагностика XR (XrDiag: состояние OpenXR/VRS/MSAA и PNG кадра вида) включена?
static func perf_diag(s: String) -> bool:
	return s == "diag"


## Слои позади сцены (руки и луч поверх панели)?
static func layers_behind(s: String) -> bool:
	return s == "behind"


## Ручки материалов ассетов из блока [assets] того же файла (AssetMaterials.tune_from_config — зона Blender, контракт неизменный); звать ДО построения узлов
## (материалы ставятся при построении). Неизвестные ручки (в том числе уже удалённые) AssetMaterials пропускает с предупреждением.
func apply_assets(paths: PackedStringArray = NetConfig.default_paths()) -> void:
	var script: GDScript = AssetMaterials   # ссылка на скрипт: у статического имени класса has_method недоступен
	if script.has_method("tune_from_config"):
		for p in paths:
			if not FileAccess.file_exists(p):
				continue
			var cf := ConfigFile.new()
			if cf.load(p) == OK:
				script.call("tune_from_config", cf)
			break


## 3D-сглаживание окна/вьюпорта (плоский клиент и XR: у XR оно задаётся на том же корневом Viewport): MSAA; экранного сглаживания нет (FXAA снимал фовеацию).
func apply_msaa(vp: Viewport) -> void:
	vp.msaa_3d = msaa_mode(msaa)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


## Фовеация интерфейса OpenXR (масштаб не меняем: 1,0). Свойства проверяются через `in`: у других XRInterface (и у разных версий Godot) их может не быть.
## Возвращает имена свойств, которых у интерфейса нет (в журнал).
func apply_xr(iface: Object) -> PackedStringArray:
	var missing := PackedStringArray()
	if "foveation_level" in iface:
		iface.set("foveation_level", foveation)
	else:
		missing.append("foveation_level")
	return missing


## Поля строки журнала `render …` (MbLog).
func log_fields() -> Dictionary:
	return {"msaa": msaa, "layers": layers, "perf": perf, "volumetric": volumetric, "bench": bench if bench != "" else "off", "probe": probe if probe != "" else "off", "foveation": foveation,
		"file": file_path if not file_path.is_empty() else "none"}
