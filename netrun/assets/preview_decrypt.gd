extends Node3D
## Кадры расшифровки шарда на деке запястья (К7): вкладка ДОБЫЧА с кнопкой «РАСШИФРОВАТЬ» (и без неё, когда дешифратор слабее шарда), сетка шифр-замка, итог «ОТКРЫТ».
## Плотность пикселей как у Pico 4 (≈ 20 px на градус: vFOV 32° при высоте окна 648 px), панель на 45 см от камеры: список — в масштабе запястья (0,75), сетка — в
## масштабе заряда (WorldUI.CHARGE_DECK_SCALE = 1). Запуск на дисплее devbox отдельным процессом:
## DISPLAY=:0 godot --path netrun --display-driver x11 --resolution 1152x648 res://assets/preview_decrypt.tscn -- --out=/каталог [--only=loot,run,done]

var _out := "/tmp/decrypt_shots"
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
	await _shot("loot", WorldUI.WRIST_DECK_SCALE, func(): _loot())
	await _shot("run", WorldUI.CHARGE_DECK_SCALE, func(): _run())
	await _shot("done", WorldUI.CHARGE_DECK_SCALE, func(): _deck.apply_charge_end({"kind": WorldMsg.EV_BK_END, "mode": "decrypt", "outcome": "SUCCESS", "decrypted": true, "title": "Схемы склада"}))
	get_tree().quit()


## ДОБЫЧА: зашифрованный шард тира 2 (дешифратор тира 2 есть — кнопка), тира 3 (дешифратора такого тира нет — кнопки нет), открытый шард и демон.
func _loot() -> void:
	_deck.charge_view().hide_all()
	_deck._end_charge_view()
	var daemons := [{"id": "d", "effect": "DECRYPT", "tier": 2}, {"id": "g", "effect": "GHOST", "tier": 1}]
	_deck.set_deck({"daemons": [], "selected": "", "ram": 10, "used": 4, "ram_default": false})
	_deck.set_loot([
		{"id": "s2", "kind": "shard", "tier": 2, "title": "Схемы склада", "enc": true, "give": true},
		{"id": "s3", "kind": "shard", "tier": 3, "title": "Ключи охраны", "enc": true, "give": true},
		{"id": "s1", "kind": "shard", "tier": 1, "title": "Накладная", "enc": false, "give": true},
		{"id": "d1", "kind": "daemon", "tier": 1, "title": "Дрожь", "enc": false, "give": true},
	], 12, daemons)
	_deck.select_tab(DeckPanel.TAB_LOOT)


func _run() -> void:
	var run := BreachRun.for_decrypt(2, 11)
	var lock := run.attempt.daemons[0] as BreachDaemon
	var m := BreachMirror.from_event({"kind": WorldMsg.EV_BK, "mode": "decrypt", "item": "s2", "title": "Схемы склада", "vault": "", "n": 0, "tier": run.tier,
		"grid": VaultBreach.public_grid(run.attempt.grid), "targets": [{"id": lock.id, "name": lock.display_name, "effect": "DECRYPT", "cells": lock.sequence}],
		"buffer": run.attempt.buffer_size, "sec": run.timer_sec})
	_deck.begin_charge(m, "decrypt", "Схемы склада")
	var path := BreachAutoSolver.solve(m.attempt)
	for i in mini(2, path.size()):
		if _deck.charge_view().tap_cell(path[i]):
			_deck.apply_charge_tick({"cell": [path[i].x, path[i].y], "ok": true, "trap": false, "left": m.timer_sec - 4 - i, "matched": []})


func _shot(name_: String, deck_scale: float, setup: Callable) -> void:
	if not _only.is_empty() and not _only.has(name_):
		return
	setup.call()
	_deck.scale = Vector3.ONE * deck_scale
	for k in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name_])
	print("кадр ", name_)
