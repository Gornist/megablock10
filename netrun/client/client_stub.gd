extends Node
## Клиент для Pico 4: тестовая сцена и XR-риг; без очков остаётся плоский риг с понятной ошибкой в журнале.

func start(_args: PackedStringArray) -> void:
	var scene := preload("res://client/rig_test_scene.gd").new()
	add_child(scene)
	if not scene.rig.start_xr():
		print("[netrun-client] OpenXR недоступен — плоский режим")
	else:
		print("[netrun-client] OpenXR запущен, сидячий режим")
