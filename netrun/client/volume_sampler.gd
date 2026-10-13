class_name VolumeSampler
extends RefCounted
## Облако частиц по мешам модели «на лету» (план «волюметрик», способ 1 из docs/netrun-refactor-plan.md §4.1): точки равномерно по ПЛОЩАДИ
## поверхности, запись как в файле `.points` (VolumeCloud.POINT_FLOATS = 7: x, y, z, полуразмер, фаза, вид, вес). Нужен, чтобы замерять облако на очках,
## не дожидаясь генератора `.points` (Blender): файл рядом с моделью по-прежнему главнее (VolumeRegistry.spawn берёт его первым).
## Чистые функции без сцены; порядок точек — порядок выборки, поэтому любой префикс — равномерная выборка (на это рассчитан LOD VolumeCloud).

## Полуразмер частицы по умолчанию, м: ячейка пыли 0,025 м ≈ 9 px на 3 м глазами Pico; частица чуть меньше.
const HALF_SIZE := 0.012
## Доля «искр» (вид 1) среди частиц.
const SPARK_SHARE := 0.08
## Вес ребра: у границы треугольника вес 1, на глубине EDGE_BAND по барицентрическим координатам — BODY_WEIGHT.
const EDGE_BAND := 0.12
const BODY_WEIGHT := 0.35


## Точки по частям модели [{mesh: Mesh, xform: Transform3D}] (NodeAssets.mesh_parts). count точек, seed фиксирует результат.
## Пусто, если у частей нет треугольников.
static func sample_parts(parts: Array, count: int, seed_value: int) -> PackedFloat32Array:
	var tris := PackedVector3Array()
	for part in parts:
		var mesh := part["mesh"] as Mesh
		if mesh == null:
			continue
		var xf: Transform3D = part["xform"]
		for v: Vector3 in mesh.get_faces():
			tris.append(xf * v)
	return sample_triangles(tris, count, seed_value)


## Точки по списку вершин треугольников (по три подряд). Площадь-взвешенный выбор треугольника, случайная точка в нём.
static func sample_triangles(tris: PackedVector3Array, count: int, seed_value: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := tris.size() / 3
	if n == 0 or count <= 0:
		return out
	var cum := PackedFloat64Array()
	cum.resize(n)
	var total := 0.0
	for i in n:
		var a := tris[i * 3]
		total += 0.5 * (tris[i * 3 + 1] - a).cross(tris[i * 3 + 2] - a).length()
		cum[i] = total
	if total <= 0.0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	out.resize(count * VolumeCloud.POINT_FLOATS)
	for k in count:
		var t := _pick(cum, rng.randf() * total)
		var u := rng.randf()
		var v := rng.randf()
		if u + v > 1.0:   # отражение в параллелограмме: равномерно по треугольнику
			u = 1.0 - u
			v = 1.0 - v
		var a := tris[t * 3]
		var p := a + (tris[t * 3 + 1] - a) * u + (tris[t * 3 + 2] - a) * v
		var edge := minf(minf(u, v), 1.0 - u - v)   # 0 на границе, 1/3 в центре
		var w := lerpf(1.0, BODY_WEIGHT, clampf(edge / EDGE_BAND, 0.0, 1.0))
		var o := k * VolumeCloud.POINT_FLOATS
		out[o] = p.x
		out[o + 1] = p.y
		out[o + 2] = p.z
		out[o + 3] = HALF_SIZE
		out[o + 4] = rng.randf()
		out[o + 5] = 1.0 if rng.randf() < SPARK_SHARE else 0.0
		out[o + 6] = w
	return out


## Габарит набора точек (с запасом на полуразмер).
static func bounds_of(points: PackedFloat32Array) -> AABB:
	var n := points.size() / VolumeCloud.POINT_FLOATS
	if n == 0:
		return AABB()
	var box := AABB(Vector3(points[0], points[1], points[2]), Vector3.ZERO)
	for i in range(1, n):
		var o := i * VolumeCloud.POINT_FLOATS
		box = box.expand(Vector3(points[o], points[o + 1], points[o + 2]))
	return box.grow(HALF_SIZE)


## Индекс треугольника по накопленной площади (бинарный поиск: первый cum[i] >= x).
static func _pick(cum: PackedFloat64Array, x: float) -> int:
	var lo := 0
	var hi := cum.size() - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if cum[mid] < x:
			lo = mid + 1
		else:
			hi = mid
	return lo
