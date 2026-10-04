extends Node3D
## Кадры деки на запястье (вкладки ДЕКА и ДОБЫЧА) для оценки читаемости без очков. Плотность пикселей как у Pico 4 (≈ 20 px на градус: vFOV 32°
## при высоте окна 648 px), панель в масштабе запястья (WorldUI.WRIST_DECK_SCALE) на 45 см от камеры. Запуск на дисплее devbox отдельным процессом:
## godot --path netrun --display-driver x11 --resolution 1152x648 res://assets/preview_deck.tscn -- --out=/каталог [--only=deck,loot]

var _out := "/tmp/deck_shots"
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
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.current = true
	add_child(cam)
	var deck := DeckPanel.new()
	deck.scale = Vector3.ONE * WorldUI.WRIST_DECK_SCALE
	deck.position = Vector3(0, 0, -0.45)
	add_child(deck)
	# Данные такого же вида, какой приходит с сервера: state.cd + ev deck, склеенные HudLogic.program_entries (как в rig_test_scene).
	var cd := [
		{"id": "a", "name": "Призрак", "left": 12.0, "st": "active", "until": 118.0},
		{"id": "b", "name": "Дрожь", "left": 42.0, "st": "cooldown", "until": 142.0},
		{"id": "c", "name": "Затмение сигнала", "left": 0.0, "st": "unsupported"},
		{"id": "d", "name": "Извлечение", "left": 0.0, "st": "ready"},
	]
	var info := [
		{"id": "a", "tier": 2, "cells": ["1C", "BD", "E9"], "effect": "GHOST", "loaded": true},
		{"id": "b", "tier": 1, "cells": ["55", "7A"], "effect": "JITTER", "loaded": true},
		{"id": "c", "tier": 3, "cells": ["A7", "1C", "BD", "55"], "effect": "BLACKOUT", "loaded": true},
		{"id": "d", "tier": 1, "cells": ["E9", "A7"], "effect": "EXTRACT_SHARD", "loaded": true},
	]
	var rows := HudLogic.program_entries(cd, info, 100.0)
	for i in rows.size():
		rows[i]["name"] = "%d %s" % [i + 1, rows[i]["name"]]
	deck.set_deck({"daemons": rows, "selected": "a", "ram": 12, "used": 11, "ram_default": true})
	deck.set_loot([
		{"id": "1", "kind": "shard", "tier": 2, "title": "Чертежи склада «Арасаки»", "enc": true},
		{"id": "2", "kind": "shard", "tier": 1, "title": "Накладная", "enc": false},
		{"id": "3", "kind": "daemon", "tier": 3, "title": "Дрожь из узла", "enc": false},
	], 120)
	var shots := [
		["deck", DeckPanel.TAB_DECK, 0.0],
		["loot", DeckPanel.TAB_LOOT, 0.0],
		["deck_wrist", DeckPanel.TAB_DECK, WorldUI.WRIST_DECK_ROLL_DEG],
		["loot_wrist", DeckPanel.TAB_LOOT, WorldUI.WRIST_DECK_ROLL_DEG],
	]
	for sh in shots:
		if not _only.is_empty() and not _only.has(String(sh[0]).trim_suffix("_wrist")):
			continue
		deck.select_tab(sh[1])
		deck.rotation = Vector3(0, 0, deg_to_rad(sh[2]))
		for k in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, sh[0]])
		print("кадр ", sh[0])
	get_tree().quit()
