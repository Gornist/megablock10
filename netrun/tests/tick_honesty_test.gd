extends GdUnitTestSuite
## Правило честности такта: игрока берут (захват) только если красная стрелка предзахвата была на его клетке в состоянии до такта; ICE никогда не входит
## в клетку игрока — если следующий шаг был бы на неё, он встаёт перед игроком и сразу переходит в Поиск (красная стрелка появляется), захват — на следующем такте.
## Property-тест на раскладках «foyer» и «foyer_tutorial»: каждый Страж на каждой фазе цикла патруля, игрок неподвижно стоит на каждой свободной клетке и виден;
## на каждом такте до него сравниваем намерение (intent → TickForecast.is_precapture) с тем, что случилось на такте. Без исключений: любое нарушение — красный тест.

const TICKS := 8


func _free_cells(grid: NodeGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in NodeGrid.cols():
		for z in NodeGrid.rows():
			var c := Vector2i(x, z)
			if not grid.is_occupied(c):
				out.append(c)
	return out


func _forecast(it: Dictionary) -> Dictionary:
	return {"c": it["cell"], "st": it["state"], "nc": it["next_cell"], "black": false}


## Прогон всех фаз × клеток. Возвращает нарушения трёх правил и число «упёрся» (чтобы тест не прошёл вхолостую): {capture, enter, bump_chain, bumps}.
## capture — захват без красной стрелки на клетке игрока до такта; enter — ICE оказался в клетке игрока; bump_chain — после «упёрся» нет Поиска,
## нет красной стрелки в состоянии после такта, захват в тот же такт или нет захвата на следующем (игрок стоит). Каждое нарушение: {sentry, phase, cell, tick}.
func _scan(layout: LayoutData) -> Dictionary:
	var grid := layout.grid()
	var cycle := LayoutCheck.cycle_ticks(layout)
	var res := {"capture": [], "enter": [], "bump_chain": [], "bumps": 0}
	var cells := _free_cells(grid)
	for si in layout.sentries.size():
		var route: Array = layout.sentries[si]["route"]
		for phase in cycle:
			for p in cells:
				var ice := TickIce.new({"sight_cells": layout.sight_cells}, route, grid)
				for _i in phase:
					ice.tick({})
				if ice.cell() == p:
					continue   # игрок не встаёт в клетку Стража (там он всегда в фокусе, отдельная история)
				var target := {"s": NodeGrid.center(p)}
				var bump_tick := -1
				for t in TICKS:
					var pre := TickForecast.is_precapture(_forecast(ice.intent()), p)
					var captured := false
					var bumped := false
					for ev: Dictionary in ice.tick(target):
						if ev["kind"] == "capture":
							captured = true
						elif ev["kind"] == "bump":
							bumped = true
					var v := {"sentry": si, "phase": phase, "cell": p, "tick": t + 1}
					if captured and not pre:
						(res["capture"] as Array).append(v)
					if ice.cell() == p:
						(res["enter"] as Array).append(v)
					if bump_tick >= 0 and t == bump_tick + 1 and not captured:
						(res["bump_chain"] as Array).append(v)   # игрок стоял, а захвата на следующем такте нет
					if bumped:
						res["bumps"] = int(res["bumps"]) + 1
						bump_tick = t
						if captured or ice.state() != TickIce.Mode.SEARCH or not TickForecast.is_precapture(_forecast(ice.intent()), p):
							(res["bump_chain"] as Array).append(v)
	return res


func _check(layout_name: String) -> void:
	var r := _scan(LayoutData.load_named(layout_name))
	assert_array(r["capture"]).is_empty()      # захват без красной стрелки на клетке в предыдущем такте
	assert_array(r["enter"]).is_empty()        # ICE не входит в клетку игрока
	assert_array(r["bump_chain"]).is_empty()   # упёрся → сразу Поиск + красная стрелка, захват не раньше следующего такта и на нём
	assert_int(r["bumps"]).is_greater(0)       # сценарий действительно встречается (тест не пустой)


func test_foyer_захват_только_после_красной_стрелки_и_упор_без_входа() -> void:
	_check("foyer")


func test_foyer_tutorial_захват_только_после_красной_стрелки_и_упор_без_входа() -> void:
	_check("foyer_tutorial")
