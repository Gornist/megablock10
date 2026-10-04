class_name DeckPointerMath
extends RefCounted
## Чистая математика указателя деки: луч из контроллера (или из камеры через курсор мыши) -> точка на панели -> пиксель SubViewport.
## Без узлов — проверяется тестами (края, промах, поворот и масштаб панели). Панель — прямоугольник в плоскости z = 0 своей системы координат,
## центр в начале, лицом к +Z (так стоит Sprite3D с текстурой SubViewport), ширина по X, высота по Y. Трансформация панели — глобальная и может
## нести масштаб (дека на запястье уменьшена); размер size_m — в системе координат самой панели, то есть до масштаба.

## Дальше этого луч панель не берёт (метры): панель на руке, до неё не дальше полутора метров.
const MAX_REACH := 3.0
## Промахи (поле reason в ответе).
const MISS_BEHIND := "behind"      ## панель позади начала луча
const MISS_BACK := "back"          ## луч идёт с обратной стороны панели (её там не видно)
const MISS_PARALLEL := "parallel"  ## луч вдоль плоскости панели
const MISS_FAR := "far"            ## дальше MAX_REACH
const MISS_OUTSIDE := "outside"    ## плоскость пересечена, но мимо прямоугольника


## Луч (origin, dir в мировых координатах) против панели. panel — глобальная Transform3D панели (центр, ориентация, масштаб 1),
## size_m — размер в метрах, view_px — размер SubViewport в пикселях. Ответ:
##   {hit: true, pos: Vector2 (пиксель SubViewport), dist: м вдоль луча, point: Vector3 (в мире), local: Vector2 (м от центра)} или
##   {hit: false, reason: MISS_*} (при MISS_OUTSIDE — ещё dist, point, local, как у попадания, но без pos). Край прямоугольника — попадание; пиксель зажат в [0, view - 1].
static func ray_to_view(origin: Vector3, dir: Vector3, panel: Transform3D, size_m: Vector2, view_px: Vector2, max_reach: float = MAX_REACH) -> Dictionary:
	var d := dir.normalized() if dir.length() > 0.0 else Vector3.ZERO
	var o := panel.affine_inverse() * origin
	var ld := panel.basis.inverse() * d
	if is_zero_approx(ld.z):
		return {"hit": false, "reason": MISS_PARALLEL}
	var t := -o.z / ld.z
	if t < 0.0:
		return {"hit": false, "reason": MISS_BEHIND}
	if ld.z > 0.0:
		return {"hit": false, "reason": MISS_BACK}   # панель смотрит на +Z; ход по лучу в сторону +Z до плоскости — это вид на неё сзади
	if t > max_reach:
		return {"hit": false, "reason": MISS_FAR}
	var p := o + ld * t
	if absf(p.x) > size_m.x * 0.5 + 1e-6 or absf(p.y) > size_m.y * 0.5 + 1e-6:
		# Мимо, но плоскость луч пересёк: точка нужна, чтобы показать «рядом с панелью» (слабый луч).
		return {"hit": false, "reason": MISS_OUTSIDE, "dist": t, "point": panel * p, "local": Vector2(p.x, p.y)}
	var px := clampf((p.x / size_m.x + 0.5) * view_px.x, 0.0, view_px.x - 1.0)
	var py := clampf((0.5 - p.y / size_m.y) * view_px.y, 0.0, view_px.y - 1.0)
	return {"hit": true, "pos": Vector2(px, py), "dist": t, "point": panel * p, "local": Vector2(p.x, p.y)}


## Обратное преобразование: пиксель SubViewport -> точка панели в мире (для проверок и подсветки).
static func view_to_world(pos: Vector2, panel: Transform3D, size_m: Vector2, view_px: Vector2) -> Vector3:
	var lx := (pos.x / view_px.x - 0.5) * size_m.x
	var ly := (0.5 - pos.y / view_px.y) * size_m.y
	return panel * Vector3(lx, ly, 0.0)


## Прокрутка стиком: сдвиг содержимого в пикселях за кадр. Стик вверх (y > 0) — к началу списка (отрицательный сдвиг).
## Мёртвая зона плавная: на её границе 0, у края — полная скорость.
static func scroll_step(stick_y: float, delta: float, px_per_s: float = 520.0, deadzone: float = 0.25) -> float:
	var a := absf(stick_y)
	if a <= deadzone:
		return 0.0
	var k := minf((a - deadzone) / (1.0 - deadzone), 1.0)
	return -signf(stick_y) * k * px_per_s * maxf(delta, 0.0)
