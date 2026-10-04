class_name BreachPanelLayout
extends RefCounted
## Где в мире стоит панель взлома (docs/netrun-deck-design.md §7.1): ≈ 48 × 32 см, на 0,65 м от сидящего в сторону хранилища, центр на 12° ниже линии
## взгляда, лицом к голове. Поза считается ОДИН раз, когда панель появилась, и дальше стоит в мире: привязка к голове (даже плавная) в VR укачивает.
## Чистая математика — проверяется тестами без сцены.

const WIDTH_M := 0.48
const HEIGHT_M := 0.32
const DIST_M := 0.65
const DROP_DEG := 12.0
## Панель появляется, когда игрок ближе этого к хранилищу (м, по плоскости), и гаснет, когда дальше HIDE_DIST (запас — чтобы не мигала на границе).
const SHOW_DIST := 2.2
const HIDE_DIST := 2.9


## Поза панели (центр, +Z — к голове) для головы head и хранилища vault.
static func pose(head: Vector3, vault: Vector3) -> Transform3D:
	var dir := Vector3(vault.x - head.x, 0.0, vault.z - head.z)
	dir = dir.normalized() if dir.length() > 0.001 else Vector3(0, 0, -1)
	var pos := head + dir * DIST_M + Vector3.DOWN * DIST_M * tan(deg_to_rad(DROP_DEG))
	var basis := Basis.looking_at(pos - head, Vector3.UP)   # -Z — от головы к панели, значит +Z (лицо Sprite3D) — к голове
	return Transform3D(basis, pos)


## Ближайшее хранилище к игроку: vaults — [{id, p: Vector3}]. current — к которому панель уже привязана (держим, пока не дальше HIDE_DIST); "" — никакого.
static func target_vault(pos: Vector3, vaults: Array, current: String = "") -> String:
	var best := ""
	var best_d := SHOW_DIST
	for v in vaults:
		var d := NodeLayout.flat_distance(pos, v["p"])
		if str(v["id"]) == current and d <= HIDE_DIST:
			return current
		if d <= best_d:
			best_d = d
			best = str(v["id"])
	return best
