extends GdUnitTestSuite
## Управление одиночной игры (client/solo_controls.gd, режим тестера xr_rig): схема, поворот щелчком 45°, прицел по центру, курсор для деки и панели взлома.


func _all_keys() -> String:
	return " | ".join(SoloControls.entries().map(func(e: Dictionary): return str(e["keys"])))


func test_схема_без_wasd_с_q_e_лкм_и_tab() -> void:
	var keys := _all_keys()
	var tokens := keys.replace("/", " ").replace("(", " ").replace(")", " ").replace("|", " ").split(" ", false)
	for k in ["W", "A", "S", "D"]:
		assert_bool(tokens.has(k)).is_false()
	assert_bool(keys.contains("Q / E")).is_true()
	assert_bool(keys.contains("ЛКМ")).is_true()
	assert_bool(keys.contains("Tab")).is_true()


func test_у_каждой_строки_схемы_есть_клавиши_действие_и_группа() -> void:
	assert_int(SoloControls.entries().size()).is_greater(5)
	for e in SoloControls.entries():
		for f in ["keys", "action", "group"]:
			assert_str(str(e.get(f, ""))).is_not_empty()


func test_строки_схемы_не_повторяются() -> void:
	var seen := {}
	for e in SoloControls.entries():
		var k := str(e["keys"])
		assert_bool(seen.has(k)).is_false()
		seen[k] = true
