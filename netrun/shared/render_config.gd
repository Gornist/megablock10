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
## pillar_lights = 4        ; сколько ближних ко входу колонн получают свет облака (0…12); цена кадра — число источников в цикле шейдера; на очках сравнивают 0 / 4 / 12
## far_cull_m = 12         ; дальше этого расстояния модели и облака не рисуются (владелец 19.10: вдали частицы превращались в сплошное чёрное); 0 — без предела, 3…60
## foveation = 0             ; фовеация (OpenXR): 0 выкл. (по умолчанию), 1 низкая, 2 средняя, 3 высокая; при msaa > 0 принудительно 0
##                           ; (MSAA с фовеацией на Adreno 650 даёт пустой экран)
##
## Удалённые ключи aa, fringe, scale, foveation_dynamic (тупики замеров 08–12.10) в старых файлах игнорируются с предупреждением.
## perf = "off"             ; счётчик кадра: "on" — раз в 5 с строка `[perf]` (FPS, среднее / максимум времени кадра, GPU-время) в журнал клиента и logcat;
##                           ; "diag" — то же плюс XrDiag: через 8 с строка `[xr-diag]` (фовеация, VRS, MSAA, размеры цели на уровне OpenXR) и PNG кадра вида в user://
## volumetric = "vault,portal,shard,exit,ice" ; объекты Сети облаком частиц (VolumeRegistry): умолчание — все модули (облако (Б) принято владельцем в очках 14.10); "off" — выкл. (стенд, сравнения), "all" или модули через запятую ("ice,vault"); точки — файл `.points` у модели, иначе сэмплер на лету
## bench = ""               ; воспроизводимый замер (BenchRun): имя пресета EyePresets (entry, north, south, vault_w, …) — через 5 с риг встаёт в его позу, 3 окна по 10 с,
##                           ; строка `[bench] ИТОГ` с медианой и min/max окон по fps / времени кадра / GPU; голову во время замера не вертеть; пусто — выкл.
## probe = ""               ; синтетическая нагрузка (LoadProbe): "quads=N,px=P,mode=blend|a2c|opaque|point" — N квадов по P пикселей, приклеенных к голове; "sweep" — серия вариантов за один запуск (ProbeSweep); пусто — выкл.
## warmup = "on"            ; прогрев шейдеров при старте (ShaderWarmup): по одному мешу каждого материала мира на 3 кадра за чёрным экраном перед камерой, чтобы компиляция пайплайнов
##                           ; прошла до первого кадра с миром ("on" по умолчанию, "off" — выкл.); итог — строка журнала `warmup.done frames=… meshes=… ms=…`
## volume_budget_ms = 0       ; регулятор плотности облаков (VolumeBudget): потолок GPU-времени кадра, мс (4…20; при 90 Гц ≈ 10,5); выше — облака редеют, ниже — густеют; 0 — выкл.

const SECTION := "render"
const KEYS := ["msaa", "layers", "far_cull_m", "pillar_lights", "foveation", "perf", "volumetric", "bench", "probe", "volume_budget_ms", "volume_impostor_m", "warmup"]
## Дальность прорисовки моделей и облаков предметов, м: дальше они не рисуются совсем (вдали облако редеет до восьмой части точек, а сплошная
## тёмная модель под ним остаётся; заодно дешевле кадр). 0 — без предела. 3…60.
const FAR_CULL_MIN := 3.0
const FAR_CULL_MAX := 60.0
const FAR_CULL_DEFAULT := 12.0
## Сколько ближних ко входу колонн получают свет облака (CloudLightPlan.pillar_max), 0…12: цикл по источникам стоит в фрагментном шейдере облака,
## число источников — цена кадра; на очках сравнивают 0 / 4 / 12.
const PILLAR_LIGHTS_MAX := 12
const PILLAR_LIGHTS_DEFAULT := 4
const VOLUME_BUDGET_MIN := 4.0
const VOLUME_BUDGET_MAX := 20.0
## Импостор дальних облаков (VolumeCloud): расстояние до камеры, мс м — дальше него облако заменяется билбордом; 0 — выкл. (по умолчанию).
const VOLUME_IMPOSTOR_MIN := 4.0
const VOLUME_IMPOSTOR_MAX := 40.0
## Ключи, удалённые рефактором (docs/netrun-refactor-plan.md): в старых netrun.cfg на очках встречаются, значения не читаем.
const LEGACY_KEYS := ["aa", "fringe", "scale", "foveation_dynamic"]
## Принятый вид (владелец 14.10, «снял, всё выглядит заебись»): все объёмные модули. Бюджет — серии на очках 13–14.10 (docs/netrun-refactor-plan.md).
const VOLUMETRIC_DEFAULT := "vault,portal,shard,exit,ice"
const PERF_VALUES := ["on", "off", "diag"]
const PERF_DEFAULT := "off"
const LAYERS_VALUES := ["on", "off", "behind"]
const LAYERS_DEFAULT := "behind"
const WARMUP_VALUES := ["on", "off"]
const WARMUP_DEFAULT := "on"
const MSAA_DEFAULT := 2
const FOVEATION_DEFAULT := 0
const FOVEATION_MAX := 3

var msaa: int = MSAA_DEFAULT
## Панели слоями композитора OpenXR: "behind" (по умолчанию) | "on" | "off".
var layers: String = LAYERS_DEFAULT
## Дальность прорисовки моделей и облаков, м (0 — без предела).
var far_cull_m: float = FAR_CULL_DEFAULT
## Света у колонн (ближние ко входу).
var pillar_lights: int = PILLAR_LIGHTS_DEFAULT
## Счётчик кадра (FramePerf): "on" | "off".
var perf: String = PERF_DEFAULT
## Объёмные модули (VolumeRegistry): "off" | "all" | список через запятую.
var volumetric: String = VOLUMETRIC_DEFAULT
## Пресет воспроизводимого замера (BenchRun) или "" — выкл.
var bench: String = ""
## Спецификация синтетической нагрузки (LoadProbe) или "" — выкл.
var probe: String = ""
## Потолок GPU-времени кадра для регулятора облаков (VolumeBudget), мс; 0 — выкл.
var volume_budget_ms: float = 0.0
## Порог импостора дальних облаков, м (VolumeCloud); 0 — выкл.
var volume_impostor_m: float = 0.0
var foveation: int = FOVEATION_DEFAULT
## Прогрев шейдеров при старте (ShaderWarmup): "on" | "off".
var warmup: String = WARMUP_DEFAULT
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
			"far_cull_m":
				var f: Variant = _number(v)
				if f != null and (float(f) == 0.0 or (float(f) >= FAR_CULL_MIN and float(f) <= FAR_CULL_MAX)):
					c.far_cull_m = float(f)
				else:
					c.warnings.append("far_cull_m: нужно 0 или число %s…%s, получено «%s» — оставлено %s" % [FAR_CULL_MIN, FAR_CULL_MAX, v, c.far_cull_m])
			"pillar_lights":
				var pl: Variant = _int(v)
				if pl != null and pl >= 0 and pl <= PILLAR_LIGHTS_MAX:
					c.pillar_lights = pl
				else:
					c.warnings.append("pillar_lights: допустимо целое 0…%d, получено «%s» — оставлено %d" % [PILLAR_LIGHTS_MAX, v, c.pillar_lights])
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
			"warmup":
				if v is String and (v as String).to_lower() in WARMUP_VALUES:
					c.warmup = (v as String).to_lower()
				else:
					c.warnings.append("warmup: допустимо «on» или «off», получено «%s» — оставлено «%s»" % [v, c.warmup])
			"volume_budget_ms":
				var n: Variant = _number(v)
				if n != null and (float(n) == 0.0 or (float(n) >= VOLUME_BUDGET_MIN and float(n) <= VOLUME_BUDGET_MAX)):
					c.volume_budget_ms = float(n)
				else:
					c.warnings.append("volume_budget_ms: нужно 0 или число %s…%s, получено «%s» — регулятор выключен" % [VOLUME_BUDGET_MIN, VOLUME_BUDGET_MAX, v])
			"volume_impostor_m":
				var d: Variant = _number(v)
				if d != null and (float(d) == 0.0 or (float(d) >= VOLUME_IMPOSTOR_MIN and float(d) <= VOLUME_IMPOSTOR_MAX)):
					c.volume_impostor_m = float(d)
				else:
					c.warnings.append("volume_impostor_m: нужно 0 или число %s…%s, получено «%s» — импостор выключен" % [VOLUME_IMPOSTOR_MIN, VOLUME_IMPOSTOR_MAX, v])
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


## Прогрев шейдеров включён в конфиге? (чистый маппинг, без сцены)
static func warmup_enabled(s: String) -> bool:
	return s == "on"


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
	return {"msaa": msaa, "layers": layers, "far_cull_m": far_cull_m, "pillar_lights": pillar_lights, "perf": perf, "volumetric": volumetric, "bench": bench if bench != "" else "off", "probe": probe if probe != "" else "off", "volume_budget_ms": volume_budget_ms, "volume_impostor_m": volume_impostor_m, "foveation": foveation, "warmup": warmup,
		"file": file_path if not file_path.is_empty() else "none"}
