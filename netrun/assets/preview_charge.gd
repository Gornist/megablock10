extends Node3D
## Кадры заряда демона на деке запястья (К6): список с кнопками «ЗАРЯДИТЬ» и «ГОТОВ К ЗАПУСКУ», сетка заряда (5×5 и 7×7), итог. Плотность пикселей как у Pico 4
## (≈ 20 px на градус: vFOV 32° при высоте окна 648 px), панель на 45 см от камеры: список — в масштабе запястья (0,75), сетка — в масштабе заряда
## (WorldUI.CHARGE_DECK_SCALE = 1). Запуск на дисплее devbox отдельным процессом:
## godot --path netrun --display-driver x11 --resolution 1152x648 res://assets/preview_charge.tscn -- --out=/каталог [--only=list,ready,run5,run7,done,run7_wrist]

var _out := "/tmp/charge_shots"
var _only: Array = []
var _deck: DeckPanel


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--only="):
			_only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.06)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.current = true
	add_child(cam)
	_deck = DeckPanel.new()
	_deck.position = Vector3(0, 0, -0.45)
	add_child(_deck)
	await _shot("list", 0.0, WorldUI.WRIST_DECK_SCALE, func(): _list("ready"))
	await _shot("ready", 0.0, WorldUI.WRIST_DECK_SCALE, func(): _list("charged"))
	await _shot("run5", 0.0, WorldUI.CHARGE_DECK_SCALE, func(): _run(1, ["1C", "BD"], "Призрак I", 1))
	await _shot("run7", 0.0, WorldUI.CHARGE_DECK_SCALE, func(): _run(3, ["E9", "1C", "55"], "Затмение III", 2))
	await _shot("run7_wrist", WorldUI.WRIST_DECK_ROLL_DEG, WorldUI.CHARGE_DECK_SCALE, func(): pass)
	await _shot("done", 0.0, WorldUI.CHARGE_DECK_SCALE, func(): _deck.apply_charge_end({"kind": WorldMsg.EV_BK_END, "mode": "charge", "daemon": "g", "outcome": "SUCCESS", "charged": true}))
	get_tree().quit()


## Список программ: Призрак, Сдвиг, Затмение (защитные) и Извлечение (заряда не имеет); state — состояние первых двух.
func _list(state: String) -> void:
	_deck.charge_view().hide_all()
	_deck._end_charge_view()
	var cd := [
		{"id": "g", "name": "Призрак", "left": 0.0, "st": state},
		{"id": "s", "name": "Сдвиг сигнала", "left": 0.0, "st": "ready"},
		{"id": "b", "name": "Затмение", "left": 142.0, "st": "cooldown", "until": 242.0},
		{"id": "x", "name": "Извлечение", "left": 0.0, "st": "ready"},
	]
	var info := [
		{"id": "g", "tier": 1, "cells": ["1C", "BD"], "effect": "GHOST", "loaded": true, "chargeable": true},
		{"id": "s", "tier": 2, "cells": ["55", "7A", "FF"], "effect": "TIMESKEW", "loaded": true, "chargeable": true},
		{"id": "b", "tier": 3, "cells": ["E9", "1C"], "effect": "BLACKOUT", "loaded": true, "chargeable": true},
		{"id": "x", "tier": 1, "cells": ["7A", "E9"], "effect": "EXTRACT_SHARD", "loaded": true, "chargeable": false},
	]
	var rows := HudLogic.program_entries(cd, info, 100.0)
	for i in rows.size():
		rows[i]["name"] = "%d %s" % [i + 1, rows[i]["name"]]
	_deck.set_deck({"daemons": rows, "selected": "g", "ram": 10, "used": 9, "ram_default": false})


## Заряд в разгаре: tier — тир демона (сетка 5/6/7), taps — сколько клеток уже нажато по решению.
func _run(tier: int, chain: Array, name_: String, taps: int) -> void:
	var d := BreachDaemon.make("g", chain, "GHOST", tier, name_)
	var run := BreachRun.for_charge(d, 11)
	var m := BreachMirror.from_event({"kind": WorldMsg.EV_BK, "mode": "charge", "daemon": "g", "vault": "", "n": 0, "tier": run.tier,
		"grid": VaultBreach.public_grid(run.attempt.grid), "targets": [{"id": "g", "name": name_, "effect": "GHOST", "cells": chain}],
		"buffer": run.attempt.buffer_size, "sec": run.timer_sec})
	_deck.begin_charge(m)
	var path := BreachAutoSolver.solve(m.attempt)
	for i in mini(taps, path.size()):
		if _deck.charge_view().tap_cell(path[i]):
			_deck.apply_charge_tick({"cell": [path[i].x, path[i].y], "ok": true, "trap": false, "left": m.timer_sec - 4 - i, "matched": []})


func _shot(name_: String, roll_deg: float, deck_scale: float, setup: Callable) -> void:
	if not _only.is_empty() and not _only.has(name_):
		return
	setup.call()
	_deck.scale = Vector3.ONE * deck_scale
	_deck.rotation = Vector3(0, 0, deg_to_rad(roll_deg))
	for k in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name_])
	print("кадр ", name_)
