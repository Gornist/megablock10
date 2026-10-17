extends GdUnitTestSuite
## Вид Датчика (client/sensor_view.gd): излучатели на краях луча лицом друг к другу, длина луча в клетках, состояние луча по полям снимка.


func test_состояние_луча_по_снимку() -> void:
	assert_int(SensorView.beam_state_of({"on": 1, "bl": 0})).is_equal(AssetMaterials.BEAM_ON)
	assert_int(SensorView.beam_state_of({"on": 0, "bl": 1})).is_equal(AssetMaterials.BEAM_BLINK)
	assert_int(SensorView.beam_state_of({"on": 0, "bl": 0})).is_equal(AssetMaterials.BEAM_OFF)


func test_излучатели_по_краям_луча_лицом_друг_к_другу() -> void:
	var s := SensorView.new()
	add_child(s)
	auto_free(s)
	s.apply_view({"id": "d1", "c": [[8, 8], [9, 8], [10, 8]], "on": 1, "bl": 0, "l": 2})
	var a := s.get_node("EmitterA") as Node3D
	var b := s.get_node("EmitterB") as Node3D
	assert_object(a.position).is_equal(NodeGrid.center(Vector2i(8, 8)) - Vector3(0.5, 0, 0))
	assert_object(b.position).is_equal(NodeGrid.center(Vector2i(10, 8)) + Vector3(0.5, 0, 0))
	assert_float(absf(wrapf(b.rotation.y - a.rotation.y, -PI, PI))).is_equal_approx(PI, 0.001)   # развёрнуты друг к другу
	var beam := a.find_child("Beam", true, false) as Node3D
	assert_float(beam.scale.z).is_equal_approx(3.0, 0.001)   # три клетки луча


func test_вспышка_срабатывания_сходит_на_нет_и_гасит_обработку() -> void:
	var s := SensorView.new()
	add_child(s)
	auto_free(s)
	s.apply_view({"id": "d1", "c": [[8, 8], [9, 8]], "on": 1, "bl": 0, "l": 2})
	assert_float(s.flash_strength()).is_equal(0.0)
	assert_bool(s.is_processing()).is_false()
	s.flash()
	assert_float(s.flash_strength()).is_equal_approx(1.0, 0.0001)
	assert_bool(s.is_processing()).is_true()
	s._process(SensorView.FLASH_SEC * 0.5)
	assert_float(s.flash_strength()).is_equal_approx(0.5, 0.0001)
	s._process(SensorView.FLASH_SEC)
	assert_float(s.flash_strength()).is_equal(0.0)
	assert_bool(s.is_processing()).is_false()
