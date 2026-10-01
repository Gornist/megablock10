class_name RigMath
extends RefCounted
## Чистая математика XR-риг: мёртвая зона, поворот рывками и плавный, скорость движения.
## Без узлов и ввода — проверяется тестами gdUnit4.

const DEADZONE := 0.2
const SNAP_THRESHOLD := 0.7      ## стик за этим порогом запускает рывок
const SNAP_RELEASE := 0.3        ## ниже этого порога стик «взведён» снова
const SNAP_STEP_DEG := 30.0
const SMOOTH_TURN_DEG_PER_S := 90.0
const MOVE_SPEED := 1.5          ## м/с, умеренная — комфорт сидя
const MAX_MOVE_SPEED := 3.0      ## жёсткий потолок, настройкой не превысить


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


## Плавный поворот: градусы за кадр (вправо — минус, как в Godot для yaw).
static func smooth_turn(stick_x: float, delta: float, speed_deg: float = SMOOTH_TURN_DEG_PER_S) -> float:
	var x := apply_deadzone(Vector2(stick_x, 0.0)).x
	return -x * speed_deg * delta


## Скорость в мировых координатах. stick: x — вправо, y — вперёд; yaw — рыскание «вперёд» (рад).
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
