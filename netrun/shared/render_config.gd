class_name RenderConfig
extends RefCounted
## Настройки сглаживания и разрешения клиента без пересборки: секция [render] того же файла netrun.cfg, что читает NetConfig
## (тот же поиск по `NetConfig.default_paths()`, берётся первый прочитанный). Владелец подбирает на очках руками (`tools/pico.sh provision`).
## Нет файла или секции — значения по умолчанию; поле неверно — по умолчанию для этого поля и строка в `warnings`
## (клиент пишет в журнал `render.warn`), клиент не падает.
##
## [render]
## msaa = 0                  ; 3D-сглаживание: 0 (выкл., по умолчанию), 2 или 4
##                           ; (замеры на Pico 4: 4× даёт вспышки, 2× — мерцание граней)
## aa = "none"              ; экранное сглаживание: "none" (по умолчанию) или "fxaa" (Viewport.screen_space_aa)
## fringe = "on"            ; мягкая обводка силуэтов (AssetMaterials.fringe_on): "on" (по умолчанию) или "off"
## layers = "off"           ; панели (дека, взлом, итог) слоями композитора OpenXR: "off" (по умолчанию), "on" или "behind"
##                           ; (чёткий текст и линии; нужна поддержка слоёв рантаймом). "on" — слой поверх сцены (руки и луч
##                           ; пропадают за панелью); "behind" — слой позади сцены с вырезом в альфе, руки и луч рисуются над панелью
## scale = 1.0               ; множитель разрешения рендера (OpenXR render_target_size_multiplier), 0,5…2,0
##                           ; (1,25 роняет частоту до 60 Гц)
## foveation = 2             ; фовеация (OpenXR): 0 выкл., 1 низкая, 2 средняя (по умолчанию, бесплатна), 3 высокая
## foveation_dynamic = false ; динамическая фовеация (уровень подбирается по нагрузке)
## perf = "off"             ; счётчик кадра: "on" — раз в 5 с строка `[perf]` (FPS, среднее / максимум времени кадра, GPU-время) в журнал клиента и logcat;
##                           ; "diag" — то же плюс XrDiag: через 8 с строка `[xr-diag]` (фовеация, VRS, MSAA, размеры цели на уровне OpenXR) и PNG кадра вида в user://
## volumetric = "off"       ; объекты Сети облаком частиц (VolumeRegistry): "off" (по умолчанию), "all" или модули через запятую ("ice,vault"); нужен файл `.points` у модели
## bench = ""               ; воспроизводимый замер (BenchRun): имя пресета EyePresets (entry, north, south, vault_w, …) — через 15 с риг встаёт в его позу, 3 прогона по 60 с,
##                           ; строка `[bench] ИТОГ` с медианой fps / времени кадра / GPU; голову во время замера не вертеть; пусто — выкл.
## probe = ""               ; синтетическая нагрузка (LoadProbe): "quads=N,px=P,mode=blend|a2c|opaque|point" — N квадов по P пикселей, приклеенных к голове; пусто — выкл.

const SECTION := "render"
const KEYS := ["msaa", "aa", "fringe", "layers", "scale", "foveation", "foveation_dynamic", "perf", "volumetric", "bench", "probe"]
const VOLUMETRIC_DEFAULT := "off"
const PERF_VALUES := ["on", "off", "diag"]
const PERF_DEFAULT := "off"
const AA_VALUES := ["none", "fxaa"]
const AA_DEFAULT := "none"
const FRINGE_VALUES := ["on", "off"]
const FRINGE_DEFAULT := "on"
const LAYERS_VALUES := ["on", "off", "behind"]
const LAYERS_DEFAULT := "off"
const MSAA_DEFAULT := 0
const SCALE_DEFAULT := 1.0
const SCALE_MIN := 0.5
const SCALE_MAX := 2.0
const FOVEATION_DEFAULT := 2
const FOVEATION_MAX := 3

var msaa: int = MSAA_DEFAULT
var aa: String = AA_DEFAULT
## Обводка силуэтов: "on" | "off".
var fringe: String = FRINGE_DEFAULT
## fringe явно задан в файле (иначе остаётся то, что выставил блок [assets]).
var fringe_set := false
## Панели слоями композитора OpenXR: "on" | "off" (по умолчанию выкл.).
var layers: String = LAYERS_DEFAULT
## Счётчик кадра (FramePerf): "on" | "off".
var perf: String = PERF_DEFAULT
## Объёмные модули (VolumeRegistry): "off" | "all" | список через запятую.
var volumetric: String = VOLUMETRIC_DEFAULT
## Пресет воспроизводимого замера (BenchRun) или "" — выкл.
var bench: String = ""
## Спецификация синтетической нагрузки (LoadProbe) или "" — выкл.
var probe: String = ""
var scale: float = SCALE_DEFAULT
var foveation: int = FOVEATION_DEFAULT
var foveation_dynamic: bool = false
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
			"aa":
				if v is String and (v as String).to_lower() in AA_VALUES:
					c.aa = (v as String).to_lower()
				else:
					c.warnings.append("aa: допустимо «none» или «fxaa», получено «%s» — оставлено «%s»" % [v, c.aa])
			"fringe":
				if v is String and (v as String).to_lower() in FRINGE_VALUES:
					c.fringe = (v as String).to_lower()
					c.fringe_set = true
				else:
					c.warnings.append("fringe: допустимо «on» или «off», получено «%s» — оставлено «%s»" % [v, c.fringe])
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
			"scale":
				var n: Variant = _number(v)
				if n != null and n >= SCALE_MIN and n <= SCALE_MAX:
					c.scale = float(n)
				else:
					c.warnings.append("scale: нужно число %s…%s, получено «%s» — оставлено %s" % [SCALE_MIN, SCALE_MAX, v, c.scale])
			"foveation":
				var n: Variant = _int(v)
				if n != null and n >= 0 and n <= FOVEATION_MAX:
					c.foveation = n
				else:
					c.warnings.append("foveation: нужно целое 0…%d, получено «%s» — оставлено %d" % [FOVEATION_MAX, v, c.foveation])
			"foveation_dynamic":
				if v is bool:
					c.foveation_dynamic = v
				elif v is String and (v as String).to_lower() in ["true", "false"]:
					c.foveation_dynamic = (v as String).to_lower() == "true"
				else:
					c.warnings.append("foveation_dynamic: нужно true или false, получено «%s» — оставлено %s" % [v, c.foveation_dynamic])
			_:
				c.warnings.append("неизвестный ключ «%s»: пропущен" % key)
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


## Режим Viewport.screen_space_aa по строке из конфига (чистый маппинг, без сцены): "fxaa" — FXAA, иначе выключено.
static func aa_mode(s: String) -> Viewport.ScreenSpaceAA:
	if s == "fxaa":
		return Viewport.SCREEN_SPACE_AA_FXAA
	return Viewport.SCREEN_SPACE_AA_DISABLED


## Обводка силуэтов включена? (чистый маппинг, без сцены)
static func fringe_enabled(s: String) -> bool:
	return s != "off"


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


## Настройки материалов ассетов; звать ДО построения узлов (материалы ставятся при построении).
## Сначала блок [assets] того же файла (AssetMaterials.tune_from_config, если он уже есть), затем fringe из [render] — он перекрывает,
## но только если задан в файле.
func apply_fringe(paths: PackedStringArray = NetConfig.default_paths()) -> void:
	var script: GDScript = AssetMaterials   # ссылка на скрипт: у статического имени класса has_method недоступен
	if script.has_method("tune_from_config"):
		for p in paths:
			if not FileAccess.file_exists(p):
				continue
			var cf := ConfigFile.new()
			if cf.load(p) == OK:
				script.call("tune_from_config", cf)
			break
	if fringe_set:
		AssetMaterials.fringe_on = fringe_enabled(fringe)


## 3D-сглаживание окна/вьюпорта (плоский клиент и XR: у XR оно задаётся на том же корневом Viewport): MSAA и FXAA.
func apply_msaa(vp: Viewport) -> void:
	vp.msaa_3d = msaa_mode(msaa)
	vp.screen_space_aa = aa_mode(aa)


## Масштаб и фовеация интерфейса OpenXR. Свойства проверяются через `in`: у других XRInterface (и у разных версий Godot) их может не быть.
## Возвращает имена свойств, которых у интерфейса нет (в журнал).
func apply_xr(iface: Object) -> PackedStringArray:
	var missing := PackedStringArray()
	if "render_target_size_multiplier" in iface:
		iface.set("render_target_size_multiplier", scale)
	else:
		missing.append("render_target_size_multiplier")
	if "foveation_level" in iface:
		iface.set("foveation_level", foveation)
	else:
		missing.append("foveation_level")
	if "foveation_dynamic" in iface:
		iface.set("foveation_dynamic", foveation_dynamic)
	else:
		missing.append("foveation_dynamic")
	return missing


## Поля строки журнала `render …` (MbLog).
func log_fields() -> Dictionary:
	return {"msaa": msaa, "aa": aa, "fringe": fringe, "layers": layers, "perf": perf, "volumetric": volumetric, "bench": bench if bench != "" else "off", "probe": probe if probe != "" else "off", "scale": scale, "foveation": foveation, "dynamic": foveation_dynamic,
		"file": file_path if not file_path.is_empty() else "none"}
