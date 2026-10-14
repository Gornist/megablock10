extends GdUnitTestSuite
## Вид Маяка (client/beacon_view.gd): угол головы по направлению клетки, клетка и дальность из снимка, узлы Head и Beam модели на месте.


func test_угол_головы_по_направлению() -> void:
	assert_float(BeaconView.yaw_of(Vector2i(0, -1))).is_equal_approx(0.0, 0.001)                 # север
	assert_float(BeaconView.yaw_of(Vector2i(1, -1))).is_equal_approx(deg_to_rad(-45.0), 0.001)   # северо-восток
	assert_float(BeaconView.yaw_of(Vector2i(1, 0))).is_equal_approx(deg_to_rad(-90.0), 0.001)    # восток
	assert_float(absf(BeaconView.yaw_of(Vector2i(0, 1)))).is_equal_approx(PI, 0.001)             # юг


func test_вид_берёт_клетку_дальность_и_угол_из_снимка() -> void:
	var b := BeaconView.new()
	add_child(b)
	auto_free(b)
	b.apply_view({"id": "o1", "c": [8, 8], "d": [1, 0], "nd": [1, 1], "aw": 0, "r": 6.0})
	assert_object(b.position).is_equal(NodeGrid.center(Vector2i(8, 8)))
	assert_float(b.head_yaw()).is_equal_approx(deg_to_rad(-90.0), 0.001)   # первый кадр — без плавного поворота
	var beam := b.find_child("Beam", true, false) as Node3D
	assert_object(beam).is_not_null()
	assert_object(beam.scale).is_equal(Vector3.ONE * 6.0)
