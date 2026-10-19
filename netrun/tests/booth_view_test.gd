extends GdUnitTestSuite
## Будка запасного Стража (ice/guard_booth.glb, ice.md §4 «тревога 2»): клиент ставит её по полю `bo` снимка у стены лицом в комнату; створка `Door` сдвигается, когда запасной вышел;
## лампа `Lamp` горит с тревоги 2. Раскладка test_booth кладётся в кэш LayoutData.

const NAME := "test_booth"

var _scene: Node3D


func before_test() -> void:
	LayoutData._cache[NAME] = LayoutData.parse({
		"name": NAME,
		"cells": ["V.......", "........", "........", "..#.....", "........", ".....1..", "S.......", "b.....EE"],
		"vaults": [{"cell": [0, 0], "pad": [0, 1], "ring": "outer"}],
		"ice": [],
	})
	assert_str((LayoutData._cache[NAME] as LayoutData).error).is_empty()
	_scene = preload("res://client/world_scene.gd").new()
	add_child(_scene)
	await get_tree().process_frame
	_scene.apply_node({"kind": "node", "node": "x", "title": "Т", "tier": "BASE", "r": NodeLayout.PORTAL_RADIUS, "shards": [], "portals": [], "layout": NAME})


func after_test() -> void:
	_scene.queue_free()
	LayoutData._cache.erase(NAME)


func _state(open: int) -> Dictionary:
	return {"k": 1.0, "trace": 0.0, "level": 0, "cd": [], "ice": [], "bo": [{"id": "b1", "c": [1, 15], "open": open}]}


func _booth() -> Node3D:
	return _scene.view.get_node("Room").get_node_or_null("Booth_b1") as Node3D


func test_будка_ставится_в_клетку_у_стены_лицом_в_комнату() -> void:
	_scene.apply_state(_state(0))
	var b := _booth()
	assert_object(b).is_not_null()
	assert_object(b.position).is_equal(NodeGrid.center(Vector2i(1, 15)))
	# Модель смотрит в −Z Godot: у южной стены лицом в комнату (на север) поворота нет.
	assert_float(absf(wrapf(b.rotation.y, -PI, PI))).is_less(0.001)
	assert_int(_scene.view.get_node("Room").find_children("Booth_b1", "Node3D", false, false).size()).is_equal(1)   # повторный снимок не плодит копий
	_scene.apply_state(_state(0))
	assert_int(_scene.view.get_node("Room").find_children("Booth_b1", "Node3D", false, false).size()).is_equal(1)


func test_створка_сдвигается_когда_запасной_вышел_и_возвращается_когда_ушёл() -> void:
	_scene.apply_state(_state(0))
	var door := _booth().find_child("Door", true, false) as Node3D
	assert_object(door).is_not_null()
	var rest := door.position
	_scene.apply_state(_state(1))
	assert_float(absf(door.position.x - rest.x)).is_equal_approx(NodeView.BOOTH_DOOR_SLIDE, 0.001)
	_scene.apply_state(_state(0))
	assert_float(absf(door.position.x - rest.x)).is_less(0.001)


func test_лампа_горит_с_тревоги_2() -> void:
	_scene.apply_state(_state(0))
	var lamp := _booth().find_child("Lamp", true, false) as Node3D
	assert_object(lamp).is_not_null()
	_scene.view.set_alarm_level(1)
	assert_bool(lamp.visible).is_false()
	_scene.view.set_alarm_level(2)
	assert_bool(lamp.visible).is_true()
	_scene.view.set_alarm_level(0)
	assert_bool(lamp.visible).is_false()


func test_пропавшая_из_снимка_будка_убирается() -> void:
	_scene.apply_state(_state(0))
	assert_object(_booth()).is_not_null()
	_scene.apply_state({"k": 2.0, "trace": 0.0, "level": 0, "cd": [], "ice": [], "bo": []})
	assert_object(_booth()).is_null()
