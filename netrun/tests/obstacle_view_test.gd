extends GdUnitTestSuite
## Клиент рисует препятствие одним корпусом (П7-2): область из двух и более блоков «#» — один меш pillar_block/pillar_base с материалом solid_dark,
## одиночный блок остаётся модулем pillar. Раскладка test_obstacles кладётся в кэш LayoutData.

const NAME := "test_obstacles"

var _ld: LayoutData


func before_test() -> void:
	_ld = LayoutData.parse({
		"name": NAME,
		"cells": [
			"........",
			".##.....",
			".#......",
			"........",
			"....#...",
			".....#..",
			"S......E",
			"........",
		],
		"vaults": [],
		"ice": [],
	})
	assert_str(_ld.error).is_empty()
	LayoutData._cache[NAME] = _ld


func after_test() -> void:
	LayoutData._cache.erase(NAME)


func _view() -> NodeView:
	var scene: Node3D = auto_free(preload("res://client/world_scene.gd").new())
	add_child(scene)
	scene.apply_node({"kind": "node", "node": "node_x", "title": "Тест", "tier": "BASE", "r": NodeLayout.PORTAL_RADIUS, "shards": [], "portals": [], "layout": NAME})
	return scene.view


func test_l_shape_is_one_obstacle_and_diagonal_blocks_stay_pillars() -> void:
	var view := _view()
	assert_int(view.solid_obstacles().size()).is_equal(1)
	assert_int(int(view.module_counts()["obstacle"])).is_equal(1)
	assert_int(view.pillar_positions().size()).is_equal(2)  # диагональ (4,4) и (5,5) — два одиночных блока
	assert_int(int(view.module_counts()["pillar"])).is_equal(2)


func test_one_mesh_instance_for_body_and_one_for_frame_with_solid_material() -> void:
	var view := _view()
	var room := view.get_node("Room")
	var body := room.get_node_or_null("pillar_block") as MeshInstance3D
	var frame := room.get_node_or_null("pillar_base") as MeshInstance3D
	assert_object(body).is_not_null()
	assert_object(frame).is_not_null()
	assert_int(body.mesh.get_surface_count()).is_equal(1)
	var mat := body.mesh.surface_get_material(0) as ShaderMaterial
	assert_object(mat).is_not_null()
	assert_float(float(mat.get_shader_parameter("edge_glow"))).is_equal_approx(1.0, 0.001)  # PILLAR_EDGE: те же рёбра, что у модуля pillar
	var bx := body.mesh.get_aabb()
	assert_float(bx.size.x).is_equal_approx(4.0 - 2.0 * ObstacleBody.INSET, 0.001)  # (1,1)+(2,1) в ряд: 4 м
	assert_float(bx.size.z).is_equal_approx(4.0 - 2.0 * ObstacleBody.INSET, 0.001)  # (1,1)+(1,2) в столбец: 4 м


func test_reflection_is_a_mirrored_copy_with_its_own_material() -> void:
	var view := _view()
	var room := view.get_node("Room")
	var body := room.get_node("pillar_block") as MeshInstance3D
	var refl := room.get_node("pillar_block_reflection") as MeshInstance3D
	assert_float(refl.transform.basis.y.y).is_equal_approx(-1.0, 0.001)
	assert_bool(refl.mesh.surface_get_material(0) != body.mesh.surface_get_material(0)).is_true()


func test_legacy_room_has_no_solid_obstacles() -> void:
	var scene: Node3D = auto_free(preload("res://client/world_scene.gd").new())
	add_child(scene)
	scene.apply_node({"kind": "node", "node": "node_x", "title": "Тест", "tier": "BASE", "r": NodeLayout.PORTAL_RADIUS, "shards": [], "portals": []})
	assert_int(scene.view.solid_obstacles().size()).is_equal(0)
	assert_int(int(scene.view.module_counts()["obstacle"])).is_equal(0)
