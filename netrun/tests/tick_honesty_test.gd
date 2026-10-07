extends GdUnitTestSuite
## Правило честности такта (PR B2): игрока берут или «упираются» в него, только если красная стрелка предзахвата была на его клетке в предыдущем состоянии.
## Property-тест на раскладке «foyer»: каждый Страж на фазах цикла патруля, игрок неподвижно стоит на каждой свободной клетке и виден;
## на каждом такте до него сравниваем намерение (intent → TickForecast.is_precapture) с тем, что случилось на такте (события capture / bump).

const TICKS := 8
## Фазы цикла берём с этим шагом (цикл «foyer» — 24 такта): иначе 24 фазы × 200+ клеток × 2 Стража — долго.
const PHASE_STEP := 3


func _free_cells(grid: NodeGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in NodeGrid.cols():
		for z in NodeGrid.rows():
			var c := Vector2i(x, z)
			if not grid.is_occupied(c):
				out.append(c)
	return out


## Случаи, когда событие `kind` случилось без красной стрелки на клетке игрока в состоянии до такта: {sentry, phase, cell, tick}.
func _violations(layout: LayoutData, kind: String) -> Array[Dictionary]:
	var grid := layout.grid()
	var cycle := LayoutCheck.cycle_ticks(layout)
	var bad: Array[Dictionary] = []
	var cells := _free_cells(grid)
	for si in layout.sentries.size():
		var route: Array = layout.sentries[si]["route"]
		for phase in range(0, cycle, PHASE_STEP):
			for p in cells:
				var ice := TickIce.new({"sight_cells": layout.sight_cells}, route, grid)
				for _i in phase:
					ice.tick({})
				if ice.cell() == p:
					continue   # вход в клетку самого ICE — отдельная история (нетраннер там всегда в фокусе)
				var target := {"s": NodeGrid.center(p)}
				for t in TICKS:
					var it := ice.intent()
					var fc := {"c": it["cell"], "st": it["state"], "nc": it["next_cell"], "black": false}
					var pre := TickForecast.is_precapture(fc, p)
					for ev: Dictionary in ice.tick(target):
						if ev["kind"] == kind and not pre:
							bad.append({"sentry": si, "phase": phase, "cell": p, "tick": t + 1})
	return bad


func test_захват_foyer_только_после_красной_стрелки_предзахвата() -> void:
	var bad := _violations(LayoutData.load_named("foyer"), "capture")
	assert_array(bad).is_empty()


## ИЗВЕСТНЫЙ ПРОБЕЛ (вход для следующей карточки, не чинится здесь): «наткнулся» без красной стрелки на «foyer» бывает, но только на первом же такте контакта —
## нетраннер возник на пути патруля в 1–2 клетках перед Стражем, который его ещё не видел (патрульный шаг упирается в него, Страж встаёт рядом, счётчик 6).
## Красная стрелка в этом состоянии невозможна: предзахват — это Поиск, а Страж ещё в Патруле. Дальше честность держится: захват (тест выше) всегда после стрелки.
## Тест стережёт границу: пробел только на 1-м такте контакта; если «наткнулся» без стрелки появится на 2-м такте и позже (игрока видели, а стрелки нет) — красный.
func test_наткнулся_без_красной_стрелки_только_на_первом_такте_контакта() -> void:
	var bad := _violations(LayoutData.load_named("foyer"), "bump")
	for v: Dictionary in bad:
		assert_int(v["tick"]).is_equal(1)


func test_захват_foyer_tutorial_только_после_красной_стрелки_предзахвата() -> void:
	assert_array(_violations(LayoutData.load_named("foyer_tutorial"), "capture")).is_empty()
