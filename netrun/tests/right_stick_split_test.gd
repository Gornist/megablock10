extends GdUnitTestSuite
## Правый стик: вперёд — прицел телепорта, вбок — поворот (щелчок snap 45° по умолчанию), между ними мёртвая зона по углу (Game 16.10, как в Skyrim VR).

func test_вперёд_это_прицел_без_поворота() -> void:
	var r := RigMath.split_right_stick(Vector2(0.0, 1.0), false)
	assert_float(r["turn"]).is_equal(0.0)
	assert_vector(r["aim"]).is_equal(Vector2(0.0, 1.0))


func test_вбок_это_поворот_без_прицела() -> void:
	var right := RigMath.split_right_stick(Vector2(1.0, 0.0), false)
	assert_float(right["turn"]).is_equal(1.0)
	assert_vector(right["aim"]).is_equal(Vector2.ZERO)
	var left := RigMath.split_right_stick(Vector2(-1.0, 0.1), false)
	assert_float(left["turn"]).is_equal(-1.0)
	assert_vector(left["aim"]).is_equal(Vector2.ZERO)


func test_мёртвая_зона_между_прицелом_и_поворотом_и_назад() -> void:
	var diag := Vector2(sin(deg_to_rad(50.0)), cos(deg_to_rad(50.0)))   # 50°: между 40° и 60°
	var r := RigMath.split_right_stick(diag, false)
	assert_float(r["turn"]).is_equal(0.0)
	assert_vector(r["aim"]).is_equal(Vector2.ZERO)
	var back := RigMath.split_right_stick(Vector2(0.1, -1.0), false)   # назад
	assert_float(back["turn"]).is_equal(0.0)
	assert_vector(back["aim"]).is_equal(Vector2.ZERO)


func test_границы_секторов() -> void:
	var at_aim := Vector2(sin(deg_to_rad(RigMath.AIM_SECTOR_DEG - 1.0)), cos(deg_to_rad(RigMath.AIM_SECTOR_DEG - 1.0)))
	assert_vector(RigMath.split_right_stick(at_aim, false)["aim"]).is_equal(at_aim)
	var at_turn := Vector2(sin(deg_to_rad(RigMath.TURN_SECTOR_DEG + 1.0)), cos(deg_to_rad(RigMath.TURN_SECTOR_DEG + 1.0)))
	assert_float(RigMath.split_right_stick(at_turn, false)["turn"]).is_equal(at_turn.x)


func test_пока_держится_прицел_вбок_не_поворачивает() -> void:
	var r := RigMath.split_right_stick(Vector2(1.0, 0.2), true)
	assert_float(r["turn"]).is_equal(0.0)
	assert_vector(r["aim"]).is_equal(Vector2(1.0, 0.2))


func test_слабое_отклонение_отдаётся_прицелу_для_отпускания() -> void:
	var r := RigMath.split_right_stick(Vector2(0.1, 0.0), false)
	assert_float(r["turn"]).is_equal(0.0)
	assert_vector(r["aim"]).is_equal(Vector2(0.1, 0.0))


func test_щелчок_45_градусов_по_умолчанию_и_отпущенный_вбок_стик_взводится_снова() -> void:
	assert_float(RigMath.SNAP_STEP_DEG).is_equal(45.0)
	var first := RigMath.snap_turn(RigMath.split_right_stick(Vector2(1.0, 0.0), false)["turn"], true)
	assert_float(first["delta_deg"]).is_equal(-45.0)
	var held := RigMath.snap_turn(1.0, first["armed"])
	assert_float(held["delta_deg"]).is_equal(0.0)
	var released := RigMath.snap_turn(0.0, held["armed"])
	assert_bool(released["armed"]).is_true()
