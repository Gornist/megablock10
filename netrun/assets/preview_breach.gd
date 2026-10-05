extends Node3D
## Кадры панели взлома хранилища (К3) для оценки читаемости без очков: плотность пикселей как у Pico 4 (≈ 20 px на градус: vFOV 32° при высоте окна 648 px),
## голова на 0,65 м от панели — как её ставит BreachPanelLayout.pose. Запуск на дисплее devbox отдельным процессом:
## DISPLAY=:0 godot --path netrun --display-driver x11 --resolution 1152x648 res://assets/preview_breach.tscn -- --out=/каталог [--only=idle,run,run7,result]

var _out := "/tmp/breach_shots"
var _only: Array = []


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
	var head := Vector3(0.0, 1.2, 0.0)
	var vault := Vector3(0.0, 1.0, -0.85)
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.position = head
	cam.rotation_degrees.x = -BreachPanelLayout.DROP_DEG   # игрок смотрит на панель: центр на 12° ниже горизонта
	cam.current = true
	add_child(cam)
	var ui := WorldUI.new()
	add_child(ui)
	var rig: XRRig = preload("res://client/xr_rig.tscn").instantiate()
	add_child(rig)
	ui.attach(rig)
	ui.deck.visible = false      # дека и trace с запястья в кадр не нужны
	ui.trace.visible = false
	var panel := ui.breach_panel
	panel.place(BreachPanelLayout.pose(head, vault))
	var daemons := [
		{"id": "d1", "name": "Извлечение II", "effect": "EXTRACT_SHARD", "tier": 2, "cells": ["1C", "BD", "E9"]},
		{"id": "d2", "name": "Призрак I", "effect": "GHOST", "tier": 1, "cells": ["55", "7A"]},
		{"id": "d3", "name": "Дрожь I", "effect": "JITTER", "tier": 1, "cells": ["FF", "1C", "55"]},
	]
	panel.set_context("Серверная", "HARD", daemons, 8)
	panel.set_trace(0.0)
	await _shot(panel, "idle", func(): panel.show_idle("v1", {"access": "ok"}))
	await _shot(panel, "cooldown", func(): panel.show_idle("v1", {"access": "cooldown", "left": 1500}))
	await _shot(panel, "run", func(): _run(panel, "HARD", 8, 6, 34.0))
	await _shot(panel, "run7", func(): _run(panel, "NIGHTMARE", 8, 7, 62.0))
	await _shot(panel, "result", func(): panel.apply_end({"outcome": "PARTIAL", "matched": ["d1"], "opened": ["v1"], "eddies": 5,
		"alert": "СБ получит сигнал через 2 мин", "cooldown": 1800, "early": ""}))
	get_tree().quit()


## Взлом в разгаре: пара ходов по решению, одно совпадение, ловушка в клетке. Сервера нет — ответы строим сами.
func _run(panel: BreachPanel, tier: String, ram: int, _size: int, trace: float) -> void:
	var daemons := [BreachDaemon.make("d1", ["1C", "BD", "E9"], "EXTRACT_SHARD", 2, "Извлечение II"), BreachDaemon.make("d2", ["55", "7A"], "GHOST", 1, "Призрак I")]
	var run := BreachRun.for_storage(tier, daemons, ram, 5)
	var targets: Array = []
	for d in daemons:
		targets.append({"id": d.id, "name": d.display_name, "effect": d.effect, "cells": d.sequence})
	var m := BreachMirror.from_event({"kind": WorldMsg.EV_BK, "vault": "v1", "n": 1, "tier": tier, "grid": run.attempt.grid.to_dict(),
		"targets": targets, "buffer": ram, "sec": run.timer_sec, "ice": run.ice_line(BreachRun.EVENT_INTRO)})
	panel.begin(m)
	panel.set_trace(trace)
	var path := BreachAutoSolver.solve(m.attempt)
	for i in 4:
		if panel.tap_cell(path[i]):
			panel.apply_tick({"cell": [path[i].x, path[i].y], "ok": true, "trap": false, "left": m.timer_sec - 3 - i, "matched": []})
	panel.apply_tick({"left": int(m.timer_sec * 0.5), "matched": ["d1"], "ice": run.ice_line(BreachRun.EVENT_HALF_TIME)})


func _shot(panel: BreachPanel, name: String, setup: Callable) -> void:
	if not _only.is_empty() and not _only.has(name):
		return
	setup.call()
	for k in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("кадр ", name)
