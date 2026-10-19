extends Node3D
## Кадры цельных препятствий (П7-2, пара с Blender П7-3): Г из трёх блоков, П из пяти, ряд из двух и одиночная колонна — глазами клиента (ObstacleBody + модуль pillar).
## Запуск: netrun/tools/dev.sh shot res://tests/obstacle_preview.tscn  (кадры: top, all, eye_l, eye_u, row_single; --out=каталог)
## Раскладка кладётся в кэш LayoutData под именем obstacle_demo: в данные игры её нет.

const NAME := "obstacle_demo"

var _out := "/tmp/obstacle_shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var ld := LayoutData.parse({
		"name": NAME,
		"cells": [
			"........",
			".#..###.",
			".##.#.#.",
			"........",
			"........",
			".##..#..",
			"S.......",
			"......EE",
		],
		"vaults": [],
		"ice": [],
	})
	assert(ld.error.is_empty(), ld.error)
	LayoutData._cache[NAME] = ld
	var scene: Node3D = preload("res://client/world_scene.gd").new()
	add_child(scene)
	await get_tree().process_frame
	scene.apply_node({"kind": "node", "node": NAME, "title": "Препятствия", "tier": "BASE", "r": NodeLayout.PORTAL_RADIUS, "shards": [], "portals": [], "layout": NAME})
	var cam := Camera3D.new()
	add_child(cam)
	var top := EyePresets.get_preset("top")
	cam.fov = top["fov"]
	cam.look_at_from_position(top["pos"], top["look"], top["up"])
	await _shot(cam, "top")
	cam.fov = 70.0
	cam.look_at_from_position(Vector3(0, 7.0, 2.0), Vector3(0, 0.5, -8.0), Vector3.UP)
	await _shot(cam, "all")
	cam.fov = 80.0
	cam.look_at_from_position(Vector3(-0.5, 1.6, -12.5), Vector3(-4.2, 1.0, -10.0), Vector3.UP)  # со стороны выемки Г: вогнутый угол
	await _shot(cam, "eye_l")
	cam.look_at_from_position(Vector3(3.0, 1.6, -4.0), Vector3(3.0, 1.0, -10.0), Vector3.UP)  # П открытой стороной к нам
	await _shot(cam, "eye_u")
	cam.look_at_from_position(Vector3(-1.0, 1.6, 1.0), Vector3(0.0, 1.0, -3.0), Vector3.UP)  # ряд из двух и одиночная
	await _shot(cam, "row_single")
	get_tree().quit()


func _shot(cam: Camera3D, name_: String) -> void:
	cam.current = true
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name_])
