extends GdUnitTestSuite
## Невидимые источники света облака (CloudLightPlan, решение владельца 18.10): набор по раскладке, поле `lights`, предел, доставка в AssetMaterials.


func _foyer() -> LayoutData:
	var ld := LayoutData.load_named("foyer")
	assert_str(ld.error).is_empty()
	return ld


func _has_light_near(lights: Array, p: Vector3, tol: float = 0.01) -> bool:
	for l: Dictionary in lights:
		var q: Vector3 = l["p"]
		if Vector2(q.x, q.z).distance_to(Vector2(p.x, p.z)) <= tol:
			return true
	return false


func test_по_умолчанию_свет_у_входа_выхода_хранилищ_и_угроз() -> void:
	var ld := _foyer()
	var lights := CloudLightPlan.build(ld)
	assert_bool(lights.size() >= 5 and lights.size() <= CloudLightPlan.MAX).is_true()
	assert_bool(_has_light_near(lights, ld.spawn)).is_true()
	assert_bool(_has_light_near(lights, ld.exit_pos)).is_true()
	for v: Dictionary in ld.vaults:
		assert_bool(_has_light_near(lights, v["slot"])).is_true()
	for b: Dictionary in ld.beacons:
		assert_bool(_has_light_near(lights, NodeGrid.center(b["cell"]))).is_true()
	for l: Dictionary in lights:
		assert_float((l["p"] as Vector3).y).is_equal(CloudLightPlan.Y)
		assert_float(float(l["r"])).is_greater(0.0)


func test_угрозы_красные_остальное_без_цвета_и_цвет_по_умолчанию_у_Blender() -> void:
	var ld := _foyer()
	var lights := CloudLightPlan.build(ld)
	var spawn_light: Dictionary = lights[0]
	assert_bool(spawn_light.has("c")).is_false()   # вход — бирюзово-белый по умолчанию облака
	var threats := 0
	for l: Dictionary in lights:
		if l.has("c"):
			assert_object(l["c"]).is_equal(CloudLightPlan.THREAT_COLOR)
			threats += 1
	assert_int(threats).is_greater(0)   # в Фойе есть Стражи/Маяки/Датчики


func test_предел_двенадцать_важное_впереди() -> void:
	var ld := LayoutData.parse({"name": "many", "cells": ["S.1....E", "........", "........", "........", "........", "........", "........", "........"],
		"vaults": [], "ice": []})
	assert_str(ld.error).is_empty()
	for i in 20:
		ld.vaults.append({"slot": Vector3(float(i), 1.0, 0.0)})
	var lights := CloudLightPlan.build(ld)
	assert_int(lights.size()).is_equal(CloudLightPlan.MAX)
	assert_bool(_has_light_near(lights, ld.spawn)).is_true()   # вход и выход выживают, обрезаются хвостовые хранилища
	assert_bool(_has_light_near(lights, ld.exit_pos)).is_true()


func _pillar_layout(rows: Array, extra: Dictionary = {}) -> LayoutData:
	var d := {"name": "pillars", "cells": rows, "vaults": [], "ice": []}
	d.merge(extra)
	var ld := LayoutData.parse(d)
	assert_str(ld.error).is_empty()
	return ld


func _light_at(lights: Array, p: Vector3) -> Dictionary:
	for l: Dictionary in lights:
		var q: Vector3 = l["p"]
		if Vector2(q.x, q.z).distance_to(Vector2(p.x, p.z)) <= 0.01:
			return l
	return {}


func test_колонна_даёт_источник_радиус_два_без_цвета() -> void:
	var ld := _pillar_layout(["S.1#...E", "........", "........", "........", "........", "........", "........", "........"])
	var pc := NodeLayout.cell_center(3, 0)   # центр блока «#» (3, 0)
	var l := _light_at(CloudLightPlan.build(ld), pc)
	assert_bool(l.is_empty()).is_false()
	assert_float(float(l["r"])).is_equal(CloudLightPlan.R_PILLAR)
	assert_float(float(l["r"])).is_equal(2.0)
	assert_float(float(l["s"])).is_equal(1.0)
	assert_float((l["p"] as Vector3).y).is_equal(CloudLightPlan.Y)
	assert_bool(l.has("c")).is_false()   # цвет по умолчанию облака, красный — только у угроз


func test_блоки_колонн_находятся_по_карте_ближние_ко_входу_первыми() -> void:
	var ld := _pillar_layout(["S.1....E", "........", "...#....", "........", "........", "..#.....", "........", "......#."])
	var pcs := CloudLightPlan.pillar_centers(ld)
	assert_int(pcs.size()).is_equal(3)
	assert_object(pcs[0]).is_equal(NodeLayout.cell_center(3, 2))   # расстояние от входа (0,0): 13 < 29 < 85 (в блоках²)
	assert_object(pcs[1]).is_equal(NodeLayout.cell_center(2, 5))
	assert_object(pcs[2]).is_equal(NodeLayout.cell_center(6, 7))


func test_колонны_после_угроз_и_перед_центром_комнаты() -> void:
	var ld := _pillar_layout(["S.1#...E", "........", "........", "........", "........", "........", "........", "........"])
	var lights := CloudLightPlan.build(ld)
	var pc := NodeLayout.cell_center(3, 0)
	var ip := -1
	var ic := -1
	for i in lights.size():
		var q: Vector3 = lights[i]["p"]
		if Vector2(q.x, q.z).distance_to(Vector2(pc.x, pc.z)) <= 0.01:
			ip = i
		if Vector2(q.x, q.z).distance_to(Vector2(ld.room_center().x, ld.room_center().z)) <= 0.01:
			ic = i
	assert_int(ip).is_greater(-1)
	assert_int(ic).is_equal(lights.size() - 1)   # центр комнаты — последним
	assert_int(ip).is_equal(ic - 1)


func test_переполнение_колонны_вытесняются_первыми_берутся_ближние_ко_входу() -> void:
	# 61 колонна, вход, выход, портал: свободно 12 - 3 = 9 мест; центр комнаты отрезан вместе с дальними колоннами.
	var ld := _pillar_layout(["S#1#####", "########", "########", "########", "########", "########", "########", "#######E"])
	var pcs := CloudLightPlan.pillar_centers(ld)
	assert_int(pcs.size()).is_greater(9)
	var lights := CloudLightPlan.build(ld)
	assert_int(lights.size()).is_equal(CloudLightPlan.MAX)
	assert_bool(_has_light_near(lights, ld.spawn)).is_true()
	assert_bool(_has_light_near(lights, ld.exit_pos)).is_true()
	assert_bool(_has_light_near(lights, ld.portals[0])).is_true()
	for i in 9:
		assert_bool(_has_light_near(lights, pcs[i])).is_true()
	assert_bool(_has_light_near(lights, pcs[9])).is_false()
	assert_bool(_has_light_near(lights, ld.room_center())).is_false()
	# детерминированно: тот же порядок при втором построении
	assert_array(CloudLightPlan.pillar_centers(ld)).is_equal(pcs)


func after_test() -> void:
	CloudLightPlan.pillar_max = CloudLightPlan.MAX


func test_pillar_max_ограничивает_число_колонн_ближние_ко_входу() -> void:
	var ld := _pillar_layout(["S#1#####", "########", "########", "########", "########", "########", "########", "#######E"])
	var pcs := CloudLightPlan.pillar_centers(ld)
	CloudLightPlan.pillar_max = 2
	var lights := CloudLightPlan.build(ld)
	assert_bool(_has_light_near(lights, pcs[0])).is_true()
	assert_bool(_has_light_near(lights, pcs[1])).is_true()
	assert_bool(_has_light_near(lights, pcs[2])).is_false()
	assert_bool(_has_light_near(lights, ld.room_center())).is_true()   # места освободились — центр комнаты на месте
	assert_int(lights.size()).is_equal(3 + 2 + 1)   # вход, выход, портал + 2 колонны + центр


func test_pillar_max_ноль_колонн_без_света() -> void:
	var ld := _pillar_layout(["S#1#####", "########", "########", "########", "########", "########", "########", "#######E"])
	CloudLightPlan.pillar_max = 0
	var lights := CloudLightPlan.build(ld)
	for pc: Vector3 in CloudLightPlan.pillar_centers(ld):
		assert_bool(_has_light_near(lights, pc)).is_false()
	assert_int(lights.size()).is_equal(3 + 1)


func test_колонны_не_вытесняют_важное_сверху() -> void:
	var ld := _pillar_layout(["S.1#...E", "........", "........", "........", "........", "........", "........", "........"])
	for i in 20:
		ld.vaults.append({"slot": Vector3(float(i), 1.0, 0.0)})   # вход + выход + портал + хранилища уже заполняют все 12 мест
	var lights := CloudLightPlan.build(ld)
	assert_int(lights.size()).is_equal(CloudLightPlan.MAX)
	assert_bool(_has_light_near(lights, ld.spawn)).is_true()
	assert_bool(_has_light_near(lights, ld.exit_pos)).is_true()
	assert_bool(_has_light_near(lights, NodeLayout.cell_center(3, 0))).is_false()   # колонне места не нашлось
	for i in 9:
		assert_bool(_has_light_near(lights, Vector3(float(i), 1.0, 0.0))).is_true()


func test_своё_поле_lights_колонн_не_добавляет() -> void:
	var ld := _pillar_layout(["S.1#...E", "........", "........", "........", "........", "........", "........", "........"],
		{"lights": [{"cell1": [4, 4]}]})
	var lights := CloudLightPlan.build(ld)
	assert_int(lights.size()).is_equal(1)
	assert_bool(_has_light_near(lights, NodeLayout.cell_center(3, 0))).is_false()


func test_legacy_колонн_не_добавляет() -> void:
	assert_int(CloudLightPlan.build(null).size()).is_equal(3)
	assert_int(CloudLightPlan.for_legacy().size()).is_equal(3)


func test_поле_lights_раскладки_заменяет_набор_по_умолчанию() -> void:
	var ld := LayoutData.parse({"name": "custom", "cells": ["S.1....E", "........", "........", "........", "........", "........", "........", "........"],
		"lights": [{"cell1": [4, 4], "r": 5.0, "s": 2.0}, {"cell": [3, 3], "threat": true}]})
	assert_str(ld.error).is_empty()
	var lights := CloudLightPlan.build(ld)
	assert_int(lights.size()).is_equal(2)
	assert_object(lights[0]["p"]).is_equal(Vector3(NodeGrid.center(Vector2i(4, 4)).x, 1.0, NodeGrid.center(Vector2i(4, 4)).z))
	assert_float(float(lights[0]["r"])).is_equal(5.0)
	assert_float(float(lights[0]["s"])).is_equal(2.0)
	assert_bool(lights[0].has("c")).is_false()
	assert_object(lights[1]["c"]).is_equal(CloudLightPlan.THREAT_COLOR)


func test_плохое_поле_lights_даёт_ошибку_раскладки() -> void:
	var cells := ["S.1....E", "........", "........", "........", "........", "........", "........", "........"]
	assert_str(LayoutData.parse({"name": "b1", "cells": cells, "lights": "x"}).error).contains("lights")
	assert_str(LayoutData.parse({"name": "b2", "cells": cells, "lights": [{"cell1": [99, 99]}]}).error).contains("lights")
	assert_str(LayoutData.parse({"name": "b3", "cells": cells, "lights": [{"cell1": [2, 2], "r": 50.0}]}).error).contains("lights")


func test_legacy_и_пустая_раскладка_дают_вход_выход_и_шард() -> void:
	var legacy := CloudLightPlan.build(null)
	assert_int(legacy.size()).is_equal(3)
	assert_bool(_has_light_near(legacy, NodeLayout.SPAWN)).is_true()
	assert_bool(_has_light_near(legacy, NodeLayout.EXIT_POS)).is_true()
	assert_bool(_has_light_near(legacy, NodeLayout.SHARD_POS)).is_true()


func test_вид_узла_отдаёт_источники_в_материалы_и_снимает_при_выходе() -> void:
	AssetMaterials.set_cloud_lights(get_tree(), [])
	var view := NodeView.new()
	add_child(view)
	view.set_look("BASE", _foyer())
	var got := AssetMaterials.cloud_lights()
	assert_int(got.size()).is_equal(CloudLightPlan.build(_foyer()).size())
	assert_bool(_has_light_near(got, _foyer().spawn)).is_true()
	view.free()
	assert_int(AssetMaterials.cloud_lights().size()).is_equal(0)   # выход из узла: источников нет
