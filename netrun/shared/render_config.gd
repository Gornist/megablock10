class_name RenderConfig
extends RefCounted
## Настройки сглаживания и разрешения клиента без пересборки: секция [render] того же файла netrun.cfg, что читает NetConfig
## (тот же поиск по `NetConfig.default_paths()`, берётся первый прочитанный). Владелец подбирает на очках руками (`tools/pico.sh provision`).
## Нет файла или секции — значения по умолчанию; поле неверно — по умолчанию для этого поля и строка в `warnings`
## (клиент пишет в журнал `render.warn`), клиент не падает.
##
## [render]
## msaa = 4                  ; 3D-сглаживание: 0 (выкл.), 2 или 4 (по умолчанию 4)
## scale = 1.0               ; множитель разрешения рендера (OpenXR render_target_size_multiplier), 0,5…2,0
## foveation = 2             ; фовеация (OpenXR): 0 выкл., 1 низкая, 2 средняя, 3 высокая
## foveation_dynamic = false ; динамическая фовеация (уровень подбирается по нагрузке)

const SECTION := "render"
const KEYS := ["msaa", "scale", "foveation", "foveation_dynamic"]
const MSAA_DEFAULT := 4
const SCALE_DEFAULT := 1.0
const SCALE_MIN := 0.5
const SCALE_MAX := 2.0
const FOVEATION_DEFAULT := 2
const FOVEATION_MAX := 3

var msaa: int = MSAA_DEFAULT
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


## 3D-сглаживание окна/вьюпорта (плоский клиент и XR: у XR оно задаётся на том же корневом Viewport).
func apply_msaa(vp: Viewport) -> void:
	vp.msaa_3d = msaa_mode(msaa)


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
	return {"msaa": msaa, "scale": scale, "foveation": foveation, "dynamic": foveation_dynamic,
		"file": file_path if not file_path.is_empty() else "none"}
