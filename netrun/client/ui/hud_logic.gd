class_name HudLogic
extends RefCounted
## Чистая логика интерфейса в мире: цвет/текст уровня trace, форматирование перезарядки, «видна ли точка».
## Без узлов и времени. Порог уровней — как в server/trace (25/50/75), клиент server/ не читает: придут с сервера.

const LEVEL_NORMAL := 0
const LEVEL_SUSPICIOUS := 1
const LEVEL_TRACE := 2
const LEVEL_LOCKDOWN := 3
const LEVEL_FLATLINE := 4

const DEFAULT_THRESHOLDS := {"suspicious_at": 25.0, "trace_at": 50.0, "lockdown_at": 75.0, "max": 100.0}

const LEVEL_COLORS := [
	Color(0.2, 0.9, 0.5),
	Color(1.0, 0.85, 0.2),
	Color(1.0, 0.5, 0.15),
	Color(1.0, 0.15, 0.2),
	Color(0.6, 0.6, 0.65),
]
const LEVEL_NAMES := ["спокойно", "подозрение", "трассировка", "блокировка", "обрыв"]


static func level_from_value(value: float, thresholds: Dictionary = DEFAULT_THRESHOLDS) -> int:
	if value >= float(thresholds.get("max", 100.0)):
		return LEVEL_FLATLINE
	if value >= float(thresholds.get("lockdown_at", 75.0)):
		return LEVEL_LOCKDOWN
	if value >= float(thresholds.get("trace_at", 50.0)):
		return LEVEL_TRACE
	if value >= float(thresholds.get("suspicious_at", 25.0)):
		return LEVEL_SUSPICIOUS
	return LEVEL_NORMAL


static func level_color(level: int) -> Color:
	return LEVEL_COLORS[clampi(level, 0, LEVEL_COLORS.size() - 1)]


static func level_name(level: int) -> String:
	return LEVEL_NAMES[clampi(level, 0, LEVEL_NAMES.size() - 1)]


## Доля заполнения полосы 0..1.
static func trace_fraction(value: float, max_value: float = 100.0) -> float:
	if max_value <= 0.0:
		return 0.0
	return clampf(value / max_value, 0.0, 1.0)


static func trace_text(value: float, level: int) -> String:
	return "%s %d" % [level_name(level), roundi(value)]


## Перезарядка: 0 → «готово», до минуты — «N с» (вверх, чтобы не показывать «0 с» при ещё идущей), дальше — «м:сс».
static func cooldown_text(remaining_sec: float) -> String:
	if remaining_sec <= 0.0:
		return "готово"
	var s := ceili(remaining_sec)
	if s < 60:
		return "%d с" % s
	return "%d:%02d" % [s / 60, s % 60]


## Видна ли точка камере: point — в мире, cam — глобальный Transform3D камеры (взгляд в -Z).
## fov_v_deg — вертикальный угол обзора, aspect — ширина/высота. Позади камеры — не видна.
static func is_point_visible(cam: Transform3D, point: Vector3, fov_v_deg: float, aspect: float) -> bool:
	var l := cam.affine_inverse() * point
	if l.z >= 0.0:
		return false
	var depth := -l.z
	var ty := tan(deg_to_rad(fov_v_deg) * 0.5)
	return absf(l.y / depth) <= ty and absf(l.x / depth) <= ty * aspect


## Направление на экране (x вправо, y вверх, длина 1) на точку в системе камеры. Ровно по оси взгляда — вверх.
static func edge_direction(cam: Transform3D, point: Vector3) -> Vector2:
	var l := cam.affine_inverse() * point
	var d := Vector2(l.x, l.y)
	if d.length() < 0.0001:
		return Vector2.UP
	return d.normalized()


## Список демонов деки → строки панели: [{"text", "selected", "ready"}]. Демон: id, name, cooldown_left.
static func deck_rows(deck: Dictionary) -> Array:
	var rows := []
	var selected := str(deck.get("selected", ""))
	for d in deck.get("daemons", []):
		var left := float(d.get("cooldown_left", 0.0))
		rows.append({
			"text": "%s  %s" % [str(d.get("name", d.get("id", "?"))), cooldown_text(left)],
			"selected": str(d.get("id", "")) == selected,
			"ready": left <= 0.0,
		})
	return rows
