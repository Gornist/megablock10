class_name ComfortConfig
extends RefCounted
## Настройки комфорта без пересборки: необязательный файл user://comfort.cfg (ConfigFile, секция [comfort]), читается при старте
## клиента. Владелец подбирает ощущения руками на очках (tools/pico.sh tune ключ=значение), пересборка и установка APK не нужны.
## Нет файла или поле неверно — значения по умолчанию из кода (RigMath.*) и предупреждение в журнал, клиент не падает; значения
## ограничиваются допустимыми пределами. Пределы дальности и перезарядки телепорта — серверные (RigMath.TELEPORT_*_LIMIT): сервер
## проверяет сам и клиенту не доверяет, так что файлом правила не обойти. Адрес сервера и токен через этот файл не передаются.
##
## [comfort]
## turn_mode = "none"            ; "none" (по умолчанию: стик мир не вращает, поворот при телепорте) | "smooth" | "snap" (рывок 30°)
## turn_speed_deg_s = 60.0       ; угловая скорость при полном стике, 10…120
## turn_vignette = 0.45          ; доля поля зрения, закрываемая у краёв при полной скорости, 0…0,8 (0 — без виньетки)
## turn_ramp_up_s = 0.25         ; разгон поворота, 0,05…2
## turn_ramp_down_s = 0.2        ; остановка поворота, 0,05…2
## teleport_range = 4.0          ; дальность телепорта, м, 1…6 (предел сервера)
## teleport_cooldown = 1.2       ; перезарядка телепорта, с, 0,6…10 (предел сервера)
## teleport_blink_s = 0.1        ; затемнение и проявление моргания, каждое, с, 0,03…0,4
## hand_pitch_deg = -40.0        ; руки (client/hand_view.gd): поворот кисти вокруг оси X контроллера, градусы, -90…90 (вверх +); -40 подобран на Pico 4 (пальцы вдоль рукояти вниз)
## hand_offset_x = 0.0           ; смещение кисти относительно позы grip в системе контроллера, м, -0,15…0,15 (у левой руки X зеркальный)
## hand_offset_y = 0.0
## hand_offset_z = 0.0

## Наклон кисти по умолчанию, градусы: подобран на очках, владелец подтвердил («руки выглядят отлично»).
const HAND_PITCH_DEFAULT := -40.0
const PATH := "user://comfort.cfg"
const SECTION := "comfort"
const KEYS := ["turn_mode", "turn_speed_deg_s", "turn_vignette", "turn_ramp_up_s", "turn_ramp_down_s",
	"teleport_range", "teleport_cooldown", "teleport_blink_s", "hand_pitch_deg", "hand_offset_x", "hand_offset_y", "hand_offset_z"]
## Числовые поля: [наименьшее, наибольшее]. Нулевые разгон и остановка — это рывок, поэтому снизу не ноль.
const LIMITS := {
	"turn_speed_deg_s": [10.0, RigMath.TURN_SPEED_MAX_DEG_S],
	"turn_vignette": [0.0, RigMath.TURN_VIGNETTE_LIMIT],
	"turn_ramp_up_s": [0.05, 2.0],
	"turn_ramp_down_s": [0.05, 2.0],
	"teleport_range": [1.0, RigMath.TELEPORT_RANGE_LIMIT],
	"teleport_cooldown": [RigMath.TELEPORT_COOLDOWN_LIMIT, 10.0],
	"teleport_blink_s": [0.03, RigMath.TELEPORT_BLINK_LIMIT],
	"hand_pitch_deg": [-90.0, 90.0],
	"hand_offset_x": [-0.15, 0.15],
	"hand_offset_y": [-0.15, 0.15],
	"hand_offset_z": [-0.15, 0.15],
}

var turn_mode := RigMath.TURN_MODE_DEFAULT
var turn_speed_deg_s := RigMath.TURN_SPEED_DEG_S
var turn_vignette := RigMath.TURN_VIGNETTE_MAX
var turn_ramp_up_s := RigMath.TURN_RAMP_UP_SEC
var turn_ramp_down_s := RigMath.TURN_RAMP_DOWN_SEC
var teleport_range := RigMath.TELEPORT_RANGE
var teleport_cooldown := RigMath.TELEPORT_COOLDOWN
var teleport_blink_s := RigMath.TELEPORT_BLINK_SEC
var hand_pitch_deg := HAND_PITCH_DEFAULT
var hand_offset_x := 0.0
var hand_offset_y := 0.0
var hand_offset_z := 0.0
## Файл был и прочитан.
var from_file := false
## Что в файле не так (по строке на поле) — клиент пишет в журнал `comfort.warn`.
var warnings: Array[String] = []


## Прочитать файл; нет файла — значения по умолчанию без предупреждений (файл необязателен).
static func load_file(path: String = PATH) -> ComfortConfig:
	if not FileAccess.file_exists(path):
		return ComfortConfig.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		var broken := ComfortConfig.new()
		broken.warnings.append("файл %s не читается (%s): значения по умолчанию" % [path, error_string(err)])
		return broken
	var c := from_config(cfg)
	c.from_file = true
	return c


static func from_config(cfg: ConfigFile) -> ComfortConfig:
	var c := ComfortConfig.new()
	if not cfg.has_section(SECTION):
		return c
	for key in cfg.get_section_keys(SECTION):
		if not key in KEYS:
			c.warnings.append("неизвестный ключ «%s»: пропущен" % key)
			continue
		var v: Variant = cfg.get_value(SECTION, key)
		if key == "turn_mode":
			if v is String and (v == RigMath.TURN_MODE_NONE or v == RigMath.TURN_MODE_SMOOTH or v == RigMath.TURN_MODE_SNAP):
				c.turn_mode = v
			else:
				c.warnings.append("turn_mode: допустимо none, smooth или snap, получено «%s» — оставлено %s" % [v, c.turn_mode])
			continue
		var n: Variant = _number(v)
		if n == null:
			c.warnings.append("%s: не число («%s») — оставлено %s" % [key, v, c.get(key)])
			continue
		var lim: Array = LIMITS[key]
		var x := float(n)
		var clamped := clampf(x, float(lim[0]), float(lim[1]))
		if not is_equal_approx(x, clamped):
			c.warnings.append("%s: %s вне пределов %s…%s — взято %s" % [key, _fmt(x), _fmt(lim[0]), _fmt(lim[1]), _fmt(clamped)])
		c.set(key, clamped)
	return c


static func _number(v: Variant) -> Variant:
	var x := NAN
	if v is float or v is int:
		x = float(v)
	elif v is String and (v as String).is_valid_float():
		x = (v as String).to_float()
	if is_finite(x):
		return x
	return null


## Короткая запись числа для журнала: 60, 0.45, 1.2.
static func _fmt(v: float) -> String:
	return ("%.2f" % v).rstrip("0").rstrip(".")


## Поля строки журнала `comfort …` (MbLog): режим поворота и числа комфорта; file — откуда взяты.
func log_fields() -> Dictionary:
	return {
		"turn": turn_mode, "speed": _fmt(turn_speed_deg_s), "vignette": _fmt(turn_vignette),
		"ramp_up": _fmt(turn_ramp_up_s), "ramp_down": _fmt(turn_ramp_down_s),
		"range": _fmt(teleport_range), "cooldown": _fmt(teleport_cooldown), "blink": _fmt(teleport_blink_s),
		"hand": "%s,%s,%s,%s" % [_fmt(hand_pitch_deg), _fmt(hand_offset_x), _fmt(hand_offset_y), _fmt(hand_offset_z)],
		"file": "user" if from_file else "none",
	}


func apply_to(rig: XRRig) -> void:
	rig.turn_mode = turn_mode
	rig.turn_speed_deg_s = turn_speed_deg_s
	rig.turn_vignette = turn_vignette
	rig.turn_ramp_up_s = turn_ramp_up_s
	rig.turn_ramp_down_s = turn_ramp_down_s
	rig.teleport_range = teleport_range
	rig.teleport_cooldown = teleport_cooldown
	rig.teleport_blink_s = teleport_blink_s
	for hv in [rig.left_hand_view, rig.right_hand_view]:
		if hv != null:
			(hv as HandView).calibrate(hand_pitch_deg, Vector3(hand_offset_x, hand_offset_y, hand_offset_z))
