extends GdUnitTestSuite
## Сцена узла в ассетах (client/node_view.gd, ice_view.gd, avatar_view.gd): какие модели подключены по тиру узла, закрытый портал при охоте
## и локдауне, ворота выхода при уровне LOCKDOWN, шард и хранилище, ICE и чужие аватары вместо заглушек, бюджет треугольников.

const TIERS := ["BASE", "HARD", "NIGHTMARE"]
const ENV_MODULES := ["floor", "wall", "corner", "pillar", "platform", "doorway", "tunnel_ring", "ceiling", "far_field", "far_floor", "far_ceiling"]
const PORTAL := "res://assets/models/props/portal.glb"
const PORTAL_LOCKED := "res://assets/models/props/portal_locked.glb"
const GATE := "res://assets/models/env/lockdown_gate.glb"
## Узел в сборе: ТЗ ассетов (docs/netrun-assets-brief.md) просит ≤ 100 тыс. треугольников и ≈ 150 вызовов. Новый набор (штрихи, точки, потолок, пласты данных,
## отражения) осознанно тяжелее: замер 2026-10-04 — 220 тыс. треугольников (считаются все экземпляры, без отсечения) и 204 вызова. Пороги здесь = замер +10%:
## тест стережёт от роста, а не от превышения ТЗ. На Pico 4 не мерили (решение владельца), первое, что резать при провале: FAR_LAYERS в node_view.gd.
const TRIANGLE_BUDGET := 245000
const DRAW_BUDGET := 225


func _scene() -> Node3D:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	return scene


func _portal(to: String, slot: int, open: bool, tier: String = "BASE") -> Dictionary:
	var p: Vector3 = NodeLayout.PORTAL_SLOTS[slot]
	return {"to": to, "title": to, "tier": tier, "p": [p.x, p.z], "open": open}


func _shards(n: int, is_ready: bool = true) -> Array:
	var out: Array = []
	for k in n:
		var p: Vector3 = NodeLayout.SHARD_SLOTS[k]
		out.append({"id": "node_x_pk%d" % k, "p": [p.x, p.y, p.z], "ready": is_ready})
	return out


func _info(tier: String, shards: Array = [], portals: Array = []) -> Dictionary:
	return {"kind": "node", "node": "node_x", "title": "Тест", "tier": tier, "r": NodeLayout.PORTAL_RADIUS,
		"shards": shards if not shards.is_empty() else _shards(1), "portals": portals}


func _state(level: int = 0, hunt: bool = false, ice: Array = []) -> Dictionary:
	return {"trace": 0.0, "level": level, "ghost": false, "hunt": hunt, "ice": ice, "cd": []}


## Цвет тира окружения: параметр tint шейдера первого меша модуля (тир подставляется при сборке комнаты).
func _tint(root: Node, asset: String) -> Color:
	var mesh := _mesh_of(root, asset)
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as ShaderMaterial
		if m != null and m.get_shader_parameter("tint_amount") != null and float(m.get_shader_parameter("tint_amount")) > 0.5:
			return m.get_shader_parameter("tint")
	return Color.BLACK


func _mesh_of(root: Node, asset: String) -> Mesh:
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		if n.get_meta("asset", "") == asset:
			return (n as MultiMeshInstance3D).multimesh.mesh
	return null


# ---------------------------------------------------------------- комната по тиру

func test_asset_paths_do_not_depend_on_tier() -> void:
	## тир — материал (assets/ARCHITECTURE.md), а не отдельные файлы: путь модуля один на все тиры
	for tier in ["BASE", "HARD", "NIGHTMARE", "что-то новое", ""]:
		assert_str(NodeAssets.env_path("floor", tier)).is_equal("res://assets/models/env/floor.glb")


func test_room_modules_are_in_the_room_for_every_tier() -> void:
	for tier in TIERS:
		var scene := _scene()
		scene.apply_node(_info(tier))
		var used: Array = scene.view.used_assets()
		for module in ENV_MODULES:
			assert_array(used).override_failure_message("%s: нет %s" % [tier, module]).contains([NodeAssets.env_path(module, tier)])


func test_tier_changes_the_tint_of_the_room() -> void:
	var tints: Dictionary = {}
	for tier in TIERS:
		var scene := _scene()
		scene.apply_node(_info(tier))
		tints[tier] = _tint(scene.view, NodeAssets.env_path("wall", tier))
	assert_bool(tints["BASE"] != tints["HARD"] and tints["HARD"] != tints["NIGHTMARE"]).override_failure_message("тиры одного цвета: %s" % str(tints)).is_true()
	for tier in TIERS:
		assert_bool(tints[tier].b >= tints[tier].r).override_failure_message("%s: красный в окружении" % tier).is_true()


func test_next_node_rebuilds_the_room_for_its_tier() -> void:
	var scene := _scene()
	scene.apply_node(_info("HARD"))
	var hard := _tint(scene.view, NodeAssets.env_path("wall", "HARD"))
	scene.apply_node(_info("NIGHTMARE"))
	assert_str(scene.view.tier).is_equal("NIGHTMARE")
	assert_bool(_tint(scene.view, NodeAssets.env_path("wall", "NIGHTMARE")) != hard).override_failure_message("тир не сменил цвет").is_true()


func test_room_is_a_closed_8x8_grid() -> void:
	var scene := _scene()
	scene.apply_node(_info("BASE"))
	var counts: Dictionary = scene.view.module_counts()
	assert_int(counts["floor"]).is_equal(NodeLayout.GRID * NodeLayout.GRID)
	assert_int(counts["corner"]).is_equal(4)
	# периметр: 4 x 6 ячеек между углами; две из них на юге — двери выхода
	assert_int(counts["wall"] + counts["doorway"]).is_equal(4 * (NodeLayout.GRID - 2))
	assert_int(counts["doorway"]).is_equal(NodeLayout.EXIT_DOORS.size())
	assert_int(counts["platform"]).is_equal(4)
	assert_int(counts["pillar"]).is_equal(NodeLayout.PILLARS.size())
	assert_int(counts["tunnel_ring"]).is_equal(NodeLayout.EXIT_TUNNEL_SEGMENTS)


# ---------------------------------------------------------------- порталы

func test_portal_is_locked_when_destination_is_closed() -> void:
	var scene := _scene()
	scene.apply_node(_info("BASE", [], [_portal("node_02", 0, true), _portal("node_03", 1, false)]))
	assert_bool(scene.view.portal_locked(0)).is_false()
	assert_bool(scene.view.portal_locked(1)).is_true()
	assert_array(scene.view.used_assets()).contains([PORTAL, PORTAL_LOCKED])


func test_all_portals_lock_while_black_ice_hunts_the_player() -> void:
	var scene := _scene()
	scene.apply_node(_info("NIGHTMARE", [], [_portal("node_02", 0, true), _portal("node_03", 1, true)]))
	assert_array(scene.view.used_assets()).contains([PORTAL]).not_contains([PORTAL_LOCKED])
	scene.apply_state(_state(2, true))
	assert_bool(scene.view.portal_locked(0)).is_true()
	assert_bool(scene.view.portal_locked(1)).is_true()
	assert_array(scene.view.used_assets()).contains([PORTAL_LOCKED]).not_contains([PORTAL])
	scene.apply_state(_state(0, false))  # охота кончилась: порталы открываются
	assert_bool(scene.view.portal_locked(0)).is_false()
	assert_array(scene.view.used_assets()).contains([PORTAL]).not_contains([PORTAL_LOCKED])


func test_lockdown_denial_closes_that_portal_only() -> void:
	var scene := _scene()
	scene.apply_node(_info("BASE", [], [_portal("node_02", 0, true), _portal("node_03", 1, true)]))
	scene.show_portal_denied({"to": "node_03", "reason": "lockdown", "left": 30})
	assert_bool(scene.view.portal_locked(0)).is_false()
	assert_bool(scene.view.portal_locked(1)).is_true()
	# следующий снимок узла от сервера — истина: локдаун кончился, портал открыт
	scene.apply_node(_info("BASE", [], [_portal("node_02", 0, true), _portal("node_03", 1, true)]))
	assert_bool(scene.view.portal_locked(1)).is_false()


func test_portal_faces_the_room_and_labels_remain() -> void:
	var scene := _scene()
	scene.apply_node(_info("BASE", [], [_portal("node_02", 0, true)]))
	var slot: Vector3 = NodeLayout.PORTAL_SLOTS[0]
	var inst: Node3D = scene.view.portal_node(0)
	assert_vector(inst.global_position).is_equal_approx(slot, Vector3.ONE * 0.001)
	var forward := inst.global_transform.basis * Vector3(0, 0, 1)  # вход в арку с +Z
	var to_center := (NodeLayout.ROOM_CENTER - slot).normalized()
	assert_float(forward.dot(to_center)).is_greater(0.999)
	var labels := 0
	for n in scene._node_props:
		if n is Label3D:
			labels += 1
	assert_int(labels).is_equal(1)


# ---------------------------------------------------------------- выход

func test_exit_gate_replaces_the_doorway_at_lockdown_trace_level() -> void:
	var scene := _scene()
	scene.apply_node(_info("BASE"))
	var door := NodeAssets.env_path("doorway", "BASE")
	var gate := NodeAssets.env_path("lockdown_gate", "BASE")
	scene.apply_state(_state(2))
	assert_array(scene.view.used_assets()).contains([door]).not_contains([gate])
	scene.apply_state(_state(3))  # LOCKDOWN: выходы узла закрыты
	assert_bool(scene.view.exit_locked).is_true()
	assert_array(scene.view.used_assets()).contains([gate]).not_contains([door])
	scene.apply_state(_state(0))
	assert_bool(scene.view.exit_locked).is_false()
	assert_array(scene.view.used_assets()).contains([door]).not_contains([gate])


# ---------------------------------------------------------------- шарды, хранилища, мелочи

func test_ready_slot_is_open_vault_with_shard_empty_slot_is_closed_vault() -> void:
	var scene := _scene()
	scene.apply_node(_info("BASE", _shards(2)))
	var used: Array = scene.used_assets()
	assert_array(used).contains(["res://assets/models/props/vault_open.glb", "res://assets/models/props/shard.glb"])
	assert_array(used).not_contains(["res://assets/models/props/vault_closed.glb"])
	scene.apply_shards([{"id": "node_x_pk0", "ready": false}, {"id": "node_x_pk1", "ready": true}])
	assert_bool(scene.view.vault_open("node_x_pk0")).is_false()
	assert_bool(scene.view.vault_open("node_x_pk1")).is_true()
	assert_array(scene.used_assets()).contains(["res://assets/models/props/vault_closed.glb", "res://assets/models/props/vault_open.glb"])
	# шард лежит в метке ShardSlot хранилища: на 1 м над его основанием
	var slot: Vector3 = NodeLayout.SHARD_SLOTS[1]
	assert_vector((scene._pickups["node_x_pk1"] as Node3D).position).is_equal_approx(slot, Vector3(0.001, 0.06, 0.001))


func test_shard_asset_and_encrypted_variant() -> void:
	var scene := _scene()
	var shards := _shards(2)
	shards[1]["enc"] = true
	scene.apply_node(_info("BASE", shards))
	assert_str((scene._pickups["node_x_pk0"] as Node3D).get_meta("asset")).is_equal("res://assets/models/props/shard.glb")
	assert_str((scene._pickups["node_x_pk1"] as Node3D).get_meta("asset")).is_equal("res://assets/models/props/shard_encrypted.glb")


func test_node_furniture_seat_sensor_and_dead_deck() -> void:
	var scene := _scene()
	var info := _info("BASE")
	info["dead"] = [[-3.0, -3.0]]
	scene.apply_node(info)
	var used: Array = scene.view.used_assets()
	assert_array(used).contains(["res://assets/models/props/seat.glb", "res://assets/models/props/sensor.glb", "res://assets/models/props/dead_deck.glb"])
	assert_vector(scene.view.seat_node().global_position).is_equal_approx(NodeLayout.SPAWN, Vector3.ONE * 0.001)
	scene.apply_node(_info("BASE"))  # колода убрана (подобрали)
	assert_array(scene.view.used_assets()).not_contains(["res://assets/models/props/dead_deck.glb"])


func test_rig_starts_at_spawn_seat() -> void:
	var scene := _scene()
	assert_float(scene.rig.global_position.x).is_equal_approx(NodeLayout.SPAWN.x, 0.001)
	assert_float(scene.rig.global_position.z).is_equal_approx(NodeLayout.SPAWN.z, 0.001)


# ---------------------------------------------------------------- ICE

func test_ice_clip_choice_for_soft_ice() -> void:
	assert_str(IceView.clip_for(false, 0, false)).is_equal("patrol")      # PATROL
	assert_str(IceView.clip_for(false, 1, false)).is_equal("idle")        # SUSPICIOUS: стоит и смотрит
	assert_str(IceView.clip_for(false, 2, false)).is_equal("patrol")      # SEARCH: идёт к последней точке
	assert_float(IceView.speed_for(false, 2)).is_greater(IceView.speed_for(false, 0))  # поиск быстрее патруля


func test_ice_clip_choice_for_black_ice() -> void:
	assert_str(IceView.clip_for(true, 0, false)).is_equal("idle")         # патруль: парит
	assert_str(IceView.clip_for(true, 1, false)).is_equal("idle")
	assert_str(IceView.clip_for(true, 2, false)).is_equal("hunt")         # SEARCH: идёт на цель
	assert_str(IceView.clip_for(true, 3, false)).is_equal("hunt")         # HUNT
	assert_str(IceView.clip_for(true, 3, true)).is_equal("catch")         # HUNT рядом с целью: ловит
	assert_str(IceView.clip_for(true, 0, true)).is_equal("idle")          # рядом, но не на охоте: не ловит


func test_ice_models_replace_the_capsule_placeholders() -> void:
	var scene := _scene()
	scene.apply_state(_state(0, false, [
		{"id": "ice_1", "p": [1.0, 0.0, -6.0], "f": [1.0, 0.0], "s": 0, "b": 0},
		{"id": "black_1", "p": [0.0, 0.0, -12.0], "f": [1.0, 0.0], "s": 0, "b": 1}]))
	var soft: IceView = scene.ice_node("ice_1")
	var black: IceView = scene.ice_node("black_1")
	assert_str(soft.asset).is_equal("res://assets/models/ice/soft_ice.glb")
	assert_str(black.asset).is_equal("res://assets/models/ice/black_ice.glb")
	assert_bool(soft.black).is_false()
	assert_bool(black.black).is_true()
	# у ICE клипы на корневом узле (без скелета): AnimationPlayer с клипами по ТЗ
	assert_bool(soft.find_child("AnimationPlayer", true, false) is AnimationPlayer).is_true()


func test_ice_animation_follows_server_state() -> void:
	var scene := _scene()
	var ice := func(id: String, s: int, b: int, x: float = 0.0) -> Dictionary:
		return {"id": id, "p": [x, 0.0, -12.0], "f": [1.0, 0.0], "s": s, "b": b}
	scene.apply_state(_state(0, false, [ice.call("ice_1", 0, 0), ice.call("black_1", 0, 1)]))
	assert_str((scene.ice_node("ice_1") as IceView).current_clip()).is_equal("patrol")
	assert_str((scene.ice_node("black_1") as IceView).current_clip()).is_equal("idle")
	scene.apply_state(_state(2, true, [ice.call("ice_1", 1, 0), ice.call("black_1", 3, 1, 20.0)]))  # Black далеко от игрока
	assert_str((scene.ice_node("ice_1") as IceView).current_clip()).is_equal("idle")
	assert_str((scene.ice_node("black_1") as IceView).current_clip()).is_equal("hunt")
	# Black ICE дошёл до игрока (риг в точке входа): ловит
	var me: Vector3 = scene.rig.global_position
	scene.apply_state(_state(2, true, [{"id": "black_1", "p": [me.x + 1.0, 0.0, me.z], "f": [-1.0, 0.0], "s": 3, "b": 1}]))
	assert_str((scene.ice_node("black_1") as IceView).current_clip()).is_equal("catch")


func test_ice_that_left_the_snapshot_is_removed() -> void:
	# игрок прошёл порталом в узел без Black ICE: Black ICE прошлого узла не остаётся стоять в новом
	var scene := _scene()
	var soft := {"id": "ice_1", "p": [1.0, 0.0, -6.0], "f": [1.0, 0.0], "s": 0, "b": 0}
	var black := {"id": "black_1", "p": [0.0, 0.0, -12.0], "f": [1.0, 0.0], "s": 0, "b": 1}
	scene.apply_state(_state(0, false, [soft, black]))
	assert_object(scene.ice_node("black_1")).is_not_null()
	scene.apply_state(_state(0, false, [soft]))
	assert_object(scene.ice_node("black_1")).is_null()
	assert_object(scene.ice_node("ice_1")).is_not_null()
	assert_array(scene.used_assets()).not_contains([NodeAssets.BLACK_ICE])


func test_alert_marker_shows_only_when_ice_has_noticed() -> void:
	var scene := _scene()
	var ice := func(s: int) -> Dictionary:
		return {"id": "ice_1", "p": [1.0, 0.0, -6.0], "f": [1.0, 0.0], "s": s, "b": 0}
	scene.apply_state(_state(0, false, [ice.call(0)]))
	assert_bool((scene.ice_node("ice_1") as IceView).alert_visible()).is_false()
	scene.apply_state(_state(0, false, [ice.call(1)]))
	assert_bool((scene.ice_node("ice_1") as IceView).alert_visible()).is_true()


# ---------------------------------------------------------------- чужие аватары

func test_other_runners_use_the_avatar_model_with_own_colour() -> void:
	var scene := _scene()
	scene.apply_avatars({"k": 1.0, "a": [[3, -1.0, -3.0], [4, 1.0, -3.0]]})
	var a: AvatarView = scene.avatar_node("3")
	var b: AvatarView = scene.avatar_node("4")
	assert_str(a.asset).is_equal("res://assets/models/avatar/runner.glb")
	assert_bool(a.neon_color().is_equal_approx(b.neon_color())).override_failure_message("два игрока одного цвета").is_false()
	assert_bool(a.neon_color().is_equal_approx(AvatarView.color_for(3))).is_true()
	var colors: Array[Color] = []
	for id in range(1, 10):  # до 9 нетраннеров в узле различимы
		for c in colors:
			assert_float(Vector3(c.r - AvatarView.color_for(id).r, c.g - AvatarView.color_for(id).g, c.b - AvatarView.color_for(id).b).length()).is_greater(0.1)
		colors.append(AvatarView.color_for(id))


func test_runner_turns_towards_where_it_walks() -> void:
	var a: AvatarView = auto_free(AvatarView.new())
	add_child(a)
	a.setup(1)
	a.move_to(Vector3(0, 0, 0), 0.1)
	a.move_to(Vector3(1, 0, 0), 1.0)  # пошёл на +X
	assert_vector(Basis(Vector3.UP, a.rotation.y) * Vector3(0, 0, -1)).is_equal_approx(Vector3(1, 0, 0), Vector3.ONE * 0.05)  # лицо смотрит в -Z
	a.move_to(Vector3(1, 0, 0), 1.0)  # стоит: не вертится
	assert_vector(Basis(Vector3.UP, a.rotation.y) * Vector3(0, 0, -1)).is_equal_approx(Vector3(1, 0, 0), Vector3.ONE * 0.05)


func test_removed_runner_leaves_the_scene() -> void:
	var scene := _scene()
	scene.apply_avatars({"k": 1.0, "a": [[3, -1.0, -3.0]]})
	assert_object(scene.avatar_node("3")).is_not_null()
	scene.apply_avatars({"k": 2.0, "a": []})
	await get_tree().process_frame
	assert_array(scene.avatar_ids()).is_empty()


# ---------------------------------------------------------------- бюджет

## Самый тяжёлый узел: NIGHTMARE, три шарда и три портала, мёртвая дека, три ICE, девять чужих аватаров.
func _heaviest_node() -> Node3D:
	var scene := _scene()
	var info := _info("NIGHTMARE", _shards(3), [_portal("node_a", 0, true), _portal("node_b", 1, false), _portal("node_c", 2, true)])
	info["dead"] = [[-3.0, -3.0]]
	scene.apply_node(info)
	var ice: Array = []
	for id in ["ice_1", "ice_2"]:
		ice.append({"id": id, "p": [0.0, 0.0, -6.0], "f": [1.0, 0.0], "s": 0, "b": 0})
	ice.append({"id": "black_1", "p": [0.0, 0.0, -12.0], "f": [1.0, 0.0], "s": 0, "b": 1})
	scene.apply_state(_state(0, false, ice))
	var runners: Array = []
	for i in 9:
		runners.append([i + 1, -6.0 + i, -3.0])
	scene.apply_avatars({"k": 1.0, "a": runners})
	return scene


func test_assembled_node_fits_the_triangle_budget() -> void:
	var scene := _heaviest_node()
	var tris := NodeView.count_triangles(scene)
	var draws := NodeView.count_draw_calls(scene)
	print("[A3-BUDGET] треугольников: %d, вызовов отрисовки (оценка по поверхностям): %d" % [tris, draws])
	assert_int(tris).override_failure_message("узел в сборе: %d треугольников" % tris).is_less_equal(TRIANGLE_BUDGET)
	assert_int(tris).is_greater(10000)  # ассеты действительно подключены
	assert_int(draws).override_failure_message("слишком много вызовов отрисовки: %d" % draws).is_less_equal(DRAW_BUDGET)


func test_repeated_modules_are_instanced_not_duplicated() -> void:
	# 64 плитки пола (в трёх вариантах) и десятки стен — MultiMesh на вариант и поверхность, а не по узлу на плитку
	var scene := _scene()
	scene.apply_node(_info("BASE"))
	var multi: Array = scene.view.find_children("*", "MultiMeshInstance3D", true, false)
	var per_variant: Dictionary = {}  # путь варианта -> число плиток (у каждого меша варианта оно одно)
	for n in multi:
		var path := str(n.get_meta("asset", ""))
		if path in ["res://assets/models/env/floor.glb", "res://assets/models/env/floor_b.glb", "res://assets/models/env/floor_c.glb"] and not str(n.name).contains("reflection"):
			per_variant[path] = (n as MultiMeshInstance3D).multimesh.instance_count
	assert_int(per_variant.size()).is_equal(3)
	var total := 0
	for v in per_variant.values():
		total += int(v)
	assert_int(total).is_equal(NodeLayout.GRID * NodeLayout.GRID)
	assert_int(scene.view.find_children("*", "MeshInstance3D", true, false).size()).is_less(60)