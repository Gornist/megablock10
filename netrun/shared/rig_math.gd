class_name RigMath
extends RefCounted
## Чистая математика XR-рига: мёртвая зона, плавный поворот (скорость с разгоном и затуханием, виньетка), поворот рывками
## (для разработки), телепорт (прицел, вердикт, стик, моргание). Без узлов и ввода — проверяется тестами gdUnit4.
##
## Решения владельца (4 октября 2026, после теста на Pico 4): ходьба стиком отменена — движение только телепортом; рывок 30° тоже
## отменён — поворот плавный, умеренный, с виньеткой. Все числа ощущений — константы здесь; на очках их подбирают через
## user://comfort.cfg (client/comfort_config.gd) без пересборки.

const DEADZONE := 0.2
const SNAP_THRESHOLD := 0.7      ## стик за этим порогом запускает рывок
const SNAP_RELEASE := 0.3        ## ниже этого порога стик «взведён» снова
const SNAP_STEP_DEG := 30.0      ## рывок: только режим turn_mode = snap (разработка), по умолчанию не используется
const MOVE_SPEED := 1.5          ## м/с, ходьба WASD в плоской сборке с --walk (разработка); в VR ходьбы нет
const MAX_MOVE_SPEED := 3.0      ## жёсткий потолок, настройкой не превысить

# ---------------------------------------------------------------- плавный поворот
## Режимы поворота. По умолчанию стик мир не вращает вовсе: игрок поворачивается сам (вертящееся кресло), а развернуться сильнее
## помогает поворот при телепорте (facing_deg). Плавный и рывковый поворот стиком вызывали у владельца тошноту (4 октября 2026,
## проверено на Pico 4: при повороте самим игроком всё в порядке) — остались настройками для других игроков и разработки.
const TURN_MODE_NONE := "none"
const TURN_MODE_SMOOTH := "smooth"
const TURN_MODE_SNAP := "snap"
const TURN_MODE_DEFAULT := TURN_MODE_NONE
## Поворот при телепорте задаёт тот же правый стик, что и прицел: его положение (угол) относительно текущего взгляда. Слабее
## FACING_STICK_MIN стик не читаем (при отпускании он возвращается к центру — берётся последнее «держу»). В пределах FACING_DEAD_DEG от
## «вверх» поворота нет, дальше угол растёт плавно до 180° (facing_deg).
const FACING_STICK_MIN := 0.6
const FACING_DEAD_DEG := 8.0
const TURN_SPEED_DEG_S := 60.0         ## угловая скорость при полном отклонении стика
const TURN_SPEED_MAX_DEG_S := 120.0    ## потолок, настройкой не превысить
const TURN_RAMP_UP_SEC := 0.25         ## разгон от нуля до полной скорости
const TURN_RAMP_DOWN_SEC := 0.2        ## остановка с полной скорости
## Виньетка при повороте: края поля зрения темнеют пропорционально угловой скорости. 0,45 — затемнение доходит до ~45 % поля
## зрения (по радиусу) при TURN_VIGNETTE_FULL_DEG_S; потолок настройки — TURN_VIGNETTE_LIMIT.
const TURN_VIGNETTE_MAX := 0.45
const TURN_VIGNETTE_LIMIT := 0.8
const TURN_VIGNETTE_FULL_DEG_S := 60.0
const TURN_VIGNETTE_IN_SEC := 0.15
const TURN_VIGNETTE_OUT_SEC := 0.2

# ---------------------------------------------------------------- телепорт
const TELEPORT_RANGE := 4.5            ## м по полу: дальность по умолчанию (= досягаемость клеток NodeGrid.REACH_M)
const TELEPORT_COOLDOWN := 1.2         ## с: перезарядка по умолчанию
## Предел, выше которого сервер не пускает, и потолок настройки на очках: сервер не доверяет клиенту (см. NetServer.TELEPORT_*_SLACK).
const TELEPORT_RANGE_LIMIT := 6.0
const TELEPORT_COOLDOWN_LIMIT := 0.6
const TELEPORT_BLINK_SEC := 0.1        ## затемнение и проявление — каждое по этому времени; перенос — в самой тёмной точке
const TELEPORT_BLINK_LIMIT := 0.4
const TELEPORT_MIN_DIST := 0.25        ## ближе — прицел «в себя», телепорт не запрашиваем
## Шум/trace от телепорта: задел для настройки, пока не используется (сервер на телепорт trace не добавляет).
const TELEPORT_TRACE := 0.0
## Прицел правым стиком в любую сторону: отклонён за STICK_AIM_ON — показать дугу и стрелку; вернулся ниже STICK_AIM_RELEASE на
## AIM_RELEASE_HOLD секунд — отпущен (телепорт); отмена — нажатие стика. Задержка отпускания нужна, чтобы случайный провал стика
## на кадр-другой не сработал как «отпустил».
const STICK_AIM_ON := 0.7
const STICK_AIM_RELEASE := 0.3
const AIM_RELEASE_HOLD := 0.05
## Рука должна быть выше пола не меньше чем на это, чтобы считать пересечение луча с полом; иначе — по горизонтали.
const AIM_MIN_HAND_HEIGHT := 0.2
const AIM_DOWN_EPS := 0.05
## События стика прицела.
const AIM_START := "start"
const AIM_FIRE := "fire"
const AIM_CANCEL := "cancel"


## Мёртвая зона с плавным стартом: на границе 0, на краю 1, направление сохраняется.
static func apply_deadzone(v: Vector2, deadzone: float = DEADZONE) -> Vector2:
	var len := v.length()
	if len <= deadzone:
		return Vector2.ZERO
	var scaled := minf((len - deadzone) / (1.0 - deadzone), 1.0)
	return v / len * scaled


## Рывок: возвращает {"delta_deg": float, "armed": bool}. Один рывок на одно отклонение стика;
## повторный — только после возврата стика к центру (гистерезис).
static func snap_turn(stick_x: float, armed: bool, step_deg: float = SNAP_STEP_DEG) -> Dictionary:
	var ax := absf(stick_x)
	if ax < SNAP_RELEASE:
		return {"delta_deg": 0.0, "armed": true}
	if armed and ax >= SNAP_THRESHOLD:
		return {"delta_deg": -signf(stick_x) * step_deg, "armed": false}
	return {"delta_deg": 0.0, "armed": armed}


## Желаемая угловая скорость (°/с) по отклонению стика: вправо — минус, как в Godot для yaw. Потолок — TURN_SPEED_MAX_DEG_S.
static func turn_target_rate(stick_x: float, speed_deg: float = TURN_SPEED_DEG_S) -> float:
	var x := apply_deadzone(Vector2(stick_x, 0.0)).x
	return -x * clampf(speed_deg, 0.0, TURN_SPEED_MAX_DEG_S)


## Плавный поворот без разгона: градусы за кадр (оставлено для простых расчётов и тестов).
static func smooth_turn(stick_x: float, delta: float, speed_deg: float = TURN_SPEED_DEG_S) -> float:
	return turn_target_rate(stick_x, speed_deg) * delta


## Шаг угловой скорости к желаемой: разгон за ramp_up секунд до полной скорости, остановка за ramp_down; смена направления идёт
## через ноль с темпом остановки. Старт и стоп не бывают резкими: за кадр скорость меняется не больше чем на speed / ramp * delta.
static func turn_rate_step(current: float, target: float, delta: float, speed_deg: float = TURN_SPEED_DEG_S,
		ramp_up: float = TURN_RAMP_UP_SEC, ramp_down: float = TURN_RAMP_DOWN_SEC) -> float:
	var speed := clampf(speed_deg, 0.0, TURN_SPEED_MAX_DEG_S)
	var goal := clampf(target, -speed, speed)
	var cur := clampf(current, -TURN_SPEED_MAX_DEG_S, TURN_SPEED_MAX_DEG_S)
	var speeding_up := absf(goal) > absf(cur) and (cur == 0.0 or signf(cur) == signf(goal))
	var secs := maxf(ramp_up if speeding_up else ramp_down, 0.001)
	return move_toward(cur, goal, speed / secs * maxf(delta, 0.0))


## Насколько затемнять края при такой угловой скорости: 0 на месте, max_amount при TURN_VIGNETTE_FULL_DEG_S и быстрее.
static func vignette_target(rate_deg_s: float, max_amount: float = TURN_VIGNETTE_MAX) -> float:
	return clampf(absf(rate_deg_s) / TURN_VIGNETTE_FULL_DEG_S, 0.0, 1.0) * clampf(max_amount, 0.0, TURN_VIGNETTE_LIMIT)


## Виньетка догоняет цель не мгновенно: вход за in_sec, выход за out_sec (от нуля до max_amount).
static func vignette_step(current: float, target: float, delta: float, max_amount: float = TURN_VIGNETTE_MAX,
		in_sec: float = TURN_VIGNETTE_IN_SEC, out_sec: float = TURN_VIGNETTE_OUT_SEC) -> float:
	var m := clampf(max_amount, 0.0, TURN_VIGNETTE_LIMIT)
	var secs := maxf(in_sec if target > current else out_sec, 0.001)
	# Темп — от потолка не ниже стандартного: потолок настройки опустили до нуля, а виньетка ещё на экране — она всё равно гаснет за out_sec.
	return move_toward(current, target, maxf(m, TURN_VIGNETTE_MAX) / secs * maxf(delta, 0.0))


## Скорость в мировых координатах. stick: x — вправо, y — вперёд; yaw — рыскание «вперёд» (рад). Только ходьба WASD с --walk.
static func move_velocity(stick: Vector2, yaw: float, speed: float = MOVE_SPEED) -> Vector3:
	var s := apply_deadzone(stick)
	var v := minf(speed, MAX_MOVE_SPEED)
	var local := Vector3(s.x, 0.0, -s.y) * v
	return local.rotated(Vector3.UP, yaw)


## Сдвиг origin, чтобы голова оказалась над точкой target (горизонтально, высоту не трогаем).
## head_global — положение камеры в мире; возвращает новое положение origin.
static func recenter_origin(origin_pos: Vector3, head_global: Vector3, target: Vector3) -> Vector3:
	var off := Vector3(target.x - head_global.x, 0.0, target.z - head_global.z)
	return origin_pos + off


# ---------------------------------------------------------------- телепорт: прицел

## Куда целится рука. hand — положение контроллера (в плоской сборке — камеры) в мире, dir — его направление «вперёд», from — где
## игрок стоит (отсюда считается дальность), floor_y — высота пола. Луч вниз — пересечение с полом; горизонтальный и выше —
## дальняя точка по горизонтальному направлению. Результат обрезается по дальности (вдоль линии от from), затем по комнате
## (обрезка по комнате расстояние не увеличивает). Возвращает {valid, p, clamped_range, clamped_room}; valid = false —
## целиться некуда (стик вперёд, а контроллер смотрит строго вверх).
static func teleport_aim(hand: Vector3, dir: Vector3, from: Vector3, range_m: float = TELEPORT_RANGE, floor_y: float = 0.0) -> Dictionary:
	var d := dir.normalized() if dir.length() > 0.0001 else Vector3.ZERO
	var flat := Vector2(d.x, d.z)
	var raw: Vector3
	if d.y < -AIM_DOWN_EPS and hand.y - floor_y >= AIM_MIN_HAND_HEIGHT:
		var t := (hand.y - floor_y) / -d.y
		raw = Vector3(hand.x + d.x * t, floor_y, hand.z + d.z * t)
	elif flat.length() >= AIM_DOWN_EPS:
		var h := flat.normalized()
		raw = Vector3(from.x + h.x * range_m, floor_y, from.z + h.y * range_m)
	else:
		return {"valid": false, "p": Vector3(from.x, floor_y, from.z), "clamped_range": false, "clamped_room": false}
	var off := Vector2(raw.x - from.x, raw.z - from.z)
	var cut_range := off.length() > range_m
	if cut_range:
		off = off.normalized() * range_m
	var p := Vector3(from.x + off.x, floor_y, from.z + off.y)
	var inside := NodeLayout.clamp_to_room(p)
	var cut_room := not is_equal_approx(inside.x, p.x) or not is_equal_approx(inside.z, p.z)
	return {"valid": true, "p": inside, "clamped_range": cut_range, "clamped_room": cut_room}


## Точки дуги от руки к цели (квадратичная кривая Безье с подъёмом посередине) — для показа прицела.
static func arc_points(from: Vector3, to: Vector3, count: int, lift: float = -1.0) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var n := maxi(count, 2)
	var dist := from.distance_to(to)
	var h := lift if lift >= 0.0 else clampf(dist * 0.35, 0.2, 1.2)
	var mid := (from + to) * 0.5 + Vector3(0.0, h, 0.0)
	for i in n:
		var t := float(i) / float(n - 1)
		pts.append(from.lerp(mid, t).lerp(mid.lerp(to, t), t))
	return pts


## Можно ли телепортироваться: "" — да, иначе причина (WorldMsg.REASON_*). Одни и те же правила у клиента (чтобы покрасить кольцо
## красным) и у сервера (с допусками на запаздывание позы): since_last_sec — сколько прошло с прошлого телепорта (INF — не было),
## max_range — дальность по полу, min_cooldown — наименьшая пауза.
static func teleport_verdict(from: Vector3, to: Vector3, since_last_sec: float, in_tunnel: bool,
		max_range: float = TELEPORT_RANGE_LIMIT, min_cooldown: float = TELEPORT_COOLDOWN_LIMIT) -> String:
	if in_tunnel:
		return WorldMsg.REASON_TUNNEL
	if since_last_sec < min_cooldown:
		return WorldMsg.REASON_COOLDOWN
	if NodeLayout.flat_distance(from, to) > max_range:
		return WorldMsg.REASON_RANGE
	if not NodeLayout.in_room(to):
		return WorldMsg.REASON_ROOM
	return ""


## Сколько секунд перезарядки осталось (0 — готов).
static func cooldown_left(since_last_sec: float, cooldown: float = TELEPORT_COOLDOWN) -> float:
	return maxf(cooldown - since_last_sec, 0.0) if is_finite(since_last_sec) else 0.0


# ---------------------------------------------------------------- телепорт: куда смотреть после прыжка

## Поворот при телепорте, градусы вправо (по часовой): угол правого стика от «вверх» — вверх: не поворачивать, вправо: ровно 90° вправо,
## влево: 90° влево, вниз: развернуться на 180°. Плавно, без шагов. В пределах FACING_DEAD_DEG от «вверх» — 0, дальше до 90° угол
## растёт от нуля (без скачка), от 90° до 180° равен углу стика. Мир при этом не вращается: поворот применяется в самой тёмной
## точке моргания (XRRig._step_blink).
static func facing_deg(stick: Vector2) -> float:
	if stick.length() < FACING_STICK_MIN:
		return 0.0
	var a := rad_to_deg(atan2(stick.x, stick.y))
	var m := absf(a)
	if m <= FACING_DEAD_DEG:
		return 0.0
	var out := (m - FACING_DEAD_DEG) * 90.0 / (90.0 - FACING_DEAD_DEG) if m < 90.0 else m
	return signf(a) * out


# ---------------------------------------------------------------- телепорт: стик

static func aim_new() -> Dictionary:
	return {"aiming": false, "low": 0.0, "event": ""}


## Шаг прицела по правому стику (длина отклонения; направление читает facing_deg) и нажатию стика. Возвращает новое состояние
## {aiming, low, event}; event — один из AIM_START (прицел показать), AIM_FIRE (стик отпущен — телепорт), AIM_CANCEL (нажатие
## стика — отмена) или "".
static func aim_step(state: Dictionary, stick: Vector2, clicked: bool, delta: float) -> Dictionary:
	var aiming: bool = state.get("aiming", false)
	var held := stick.length()
	if not aiming:
		if held >= STICK_AIM_ON:
			return {"aiming": true, "low": 0.0, "event": AIM_START}
		return {"aiming": false, "low": 0.0, "event": ""}
	if clicked:
		return {"aiming": false, "low": 0.0, "event": AIM_CANCEL}
	if held < STICK_AIM_RELEASE:
		var low := float(state.get("low", 0.0)) + maxf(delta, 0.0)
		if low >= AIM_RELEASE_HOLD:
			return {"aiming": false, "low": 0.0, "event": AIM_FIRE}
		return {"aiming": true, "low": low, "event": ""}
	return {"aiming": true, "low": 0.0, "event": ""}


# ---------------------------------------------------------------- телепорт: моргание

static func blink_new() -> Dictionary:
	return {"phase": 0, "t": 0.0, "alpha": 0.0, "moved": false}


static func blink_start() -> Dictionary:
	return {"phase": 1, "t": 0.0, "alpha": 0.0, "moved": false}


## Шаг моргания: затемнение (phase 1) за half_sec, перенос в самой тёмной точке (moved = true ровно в одном шаге), проявление
## (phase 2) за half_sec. Слишком длинный кадр не пропускает тёмный кадр: фаза переключается не чаще раза за шаг.
static func blink_step(state: Dictionary, delta: float, half_sec: float = TELEPORT_BLINK_SEC) -> Dictionary:
	var phase: int = state.get("phase", 0)
	if phase == 0:
		return blink_new()
	var half := maxf(half_sec, 0.001)
	var t := float(state.get("t", 0.0)) + maxf(delta, 0.0)
	if phase == 1:
		if t >= half:
			return {"phase": 2, "t": 0.0, "alpha": 1.0, "moved": true}
		return {"phase": 1, "t": t, "alpha": t / half, "moved": false}
	if t >= half:
		return blink_new()
	return {"phase": 2, "t": t, "alpha": 1.0 - t / half, "moved": false}
