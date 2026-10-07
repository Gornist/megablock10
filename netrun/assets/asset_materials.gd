class_name AssetMaterials
extends RefCounted
## Подмена материалов импортированного ассета «Сети» по имени роли (shell_soft, points, streaks, solid_dark; glow_edge — устаревшая)
## на ShaderMaterial из `res://assets/shaders/`. .glb аддитивное смешивание и шейдеры не переносит,
## поэтому ассет приходит с материалами-ролями, а вид задают эти шейдеры (STYLE.md, «Что отдаёт Blender, что делает Godot»).
## Подмена идёт на экземпляре (set_surface_override_material): импортированный меш не меняется.

const SHADERS := {
	"shell_soft": preload("res://assets/shaders/shell_soft.gdshader"),
	"glow_edge": preload("res://assets/shaders/glow_edge.gdshader"),
	"points": preload("res://assets/shaders/points.gdshader"),
	"streaks": preload("res://assets/shaders/streaks.gdshader"),
	"solid_dark": preload("res://assets/shaders/solid_dark.gdshader"),
}

## Вуаль на гранях плит (меши `*_skirt` в floor, ceiling и far_*): в .glb у неё материал-роль shell_soft, а шейдер по имени меша — этот.
const SKIRT_SHADER := preload("res://assets/shaders/skirt.gdshader")
## Сплошная дымка горизонта (меш `horizon_mist` в env/horizon_band): тоже роль shell_soft, шейдер по имени меша.
const HAZE_SHADER := preload("res://assets/shaders/haze.gdshader")
## Ореол-«капля» маяка предмета (меш `beacon_halo` в узле Beacon у шарда и токена): роль shell_soft, шейдер по имени меша.
const BEACON_HALO_SHADER := preload("res://assets/shaders/beacon_halo.gdshader")
## Луч маяка (меш `beacon_beam`): штрихи (streaks) с ореолом, но спокойнее обычных — почти без дыхания и качания, гладкий (без бусин), ярче, чтобы читаться с 3 м.
const BEACON_BEAM := {"halo": 0.5, "halo_width": 2.2, "end_fade": 0.6, "breathe": 0.08, "sway": 0.003, "bead_depth": 0.0, "glow": 2.2}

## ЭКСПЕРИМЕНТ: верх стеклянного пола (меш `*_glass` в env/floor_glass_<N>): роль shell_soft, шейдер по имени меша; сторону плиты (plate_size) берём из AABB меша.
const GLASS_SHADER := preload("res://assets/shaders/glass.gdshader")

## ЭКСПЕРИМЕНТ «варианты пола» (env/floor_v<N>_<размер>, src/floor_variants.py): параметры шейдеров по номеру варианта и имени меша. Ключ — номер варианта, вложенный ключ — суффикс меша.
## `_glass` (v1 пыль — слабая дымка; v3 решётка — сплошные линии по границам клеток хода 1 м в мировых координатах, без случайных подсвеченных клеток: их принимали за занятые), `_skirt` (v2: яркая стенка ступени), `_plates` (контур верха плиты по UV).
const FLOOR_V := {
	1: {"_glass": {"glass_alpha": 0.06, "center_k": 1.0, "patch_amount": 0.5, "rim_alpha": 0.25}, "dust_streaks": {"glow": 3.2, "halo": 0.3, "halo_width": 2.0, "breathe": 0.15}},
	2: {"_skirt": {"veil_alpha": 0.32, "falloff": 0.9}, "_plates": {"uv_rim": 0.03, "edge_glow": 1.6, "edge_uneven": 0.5}},
	3: {"_glass": {"glass_alpha": 0.12, "center_k": 0.8, "patch_amount": 0.4, "rim_alpha": 0.5, "grid_alpha": 0.85, "grid_step": 1.0, "grid_width": 0.02, "grid_dot": 0.0,
			"grid_radius": 9.0, "cell_alpha": 0.0, "cell_share": 0.10}},
	4: {"_plates": {"uv_rim": 0.02, "edge_glow": 1.2, "edge_uneven": 0.7}},
}

## Параметры solid_dark.gdshader для `pillar_block`/`pillar_base` (env/pillar, env/cover) и `exit_bar_*` (env/exit_frame): ровный яркий свет рёбер без «рваности».
const PILLAR_EDGE := {"edge_glow": 2.2, "edge_uneven": 0.0}

## Параметры haze.gdshader для `edge_mist` (env/room_edge_<N>): низкая дымка вдоль границы комнаты, не туман горизонта.
const EDGE_MIST := {"haze_alpha": 0.6, "glow": 1.6, "shape": 1.0, "noise_amount": 0.35, "stripe_amount": 0.12, "stripe_count": 160.0}

## Яркость подвесных штрихов кромки комнаты (`edge_streaks_hang`): у штрихов окружения glow 1,6.
const EDGE_STREAK_GLOW := 3.4  # было 2,6: в клиентской сцене граница комнаты читалась слабо

## Цвета тиров окружения (BASE/HARD/NIGHTMARE): голубая гамма, красный в тирах не участвует.
const TIER_TINT := {
	"BASE": Color("18e6ff"),
	"HARD": Color("2a7bff"),
	"NIGHTMARE": Color("8a5cff"),
}

## Фон «пустоты» между плитами: слабая тёмная бирюзовая дымка вместо чистого чёрного (решение владельца 07.10). Замер референсов CDPR
## (`pipeline.sh stats`, 06.10): dark ≈ 0 %, lum 19–25, hor 1,4–1,9; у наших кадров на старом фоне Color(0.004, 0.008, 0.016) dark 11–36 %.
## Цель по stats на кадрах окружения BASE: dark ≤ 5 %, lum ≤ ~28, cyan ≥ 85 %, blue < 5 %, hor ≥ 1,3. Это цвет очистки (Environment.background_color):
## бесплатно по перекрытию слоёв на Pico, в отличие от нового аддитивного купола. Клиент ставит `Environment.background_color = AssetMaterials.VOID_BG`.
## Чёрные плиты `solid_dark` остаются чёрными и читаются силуэтом на бирюзовом фоне. Подбор по кадрам room_inside / room_overview / edge_view (BASE): старый фон → этот
## даёт dark 38→31, 16→13, 28→21 %, lum 21→23, 26→27, 26→28, cyan и hor не хуже; остаток dark — чёрные плиты (пол комнаты — одна плита solid_dark, потолок), не фон.
const VOID_BG := Color(0.0, 0.10, 0.13)

## Мягкий ореол штрихов окружения (streaks.gdshader): яркость хвоста, расширение квада и затухание к концам. У ассетов без тира — 0.
const ENV_HALO := 0.4
const ENV_HALO_WIDTH := 2.5
const ENV_END_FADE := 0.6

## Решётка «объёмного дисплея» (решение владельца по эксперименту): сущности (аватар, ICE) выводятся на мировой решётке 4 см, мир не квантуется,
## иначе он теряет вариативность. Шаг 10 см ломает силуэт аватара. Определяется по пути сцены ассета.
const ENTITY_LATTICE := 0.04
const ENTITY_DIRS := ["/avatar/", "/ice/"]


static func _is_entity(root: Node) -> bool:
	for d in ENTITY_DIRS:
		if root.scene_file_path.contains(d):
			return true
	return false


## tier — "BASE"/"HARD"/"NIGHTMARE" для окружения (перекрашивает свечение); пусто — цвета из вершин (ICE, аватар, дека).
## Номер варианта пола по пути сцены (`.../floor_v3_8.glb` → 3), иначе 0.
static func _floor_variant(root: Node) -> int:
	var p := root.scene_file_path
	var i := p.find("/floor_v")
	if i < 0:
		return 0
	return int(p.substr(i + 8, 1))


static func apply(root: Node, tier: String = "") -> void:
	var entity := _is_entity(root)
	var fv := _floor_variant(root)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src == null or not SHADERS.has(src.resource_name):
				continue
			var m := ShaderMaterial.new()
			m.shader = SHADERS[src.resource_name]
			if String(mi.name).ends_with("_skirt"):  # вуаль плит и дымка горизонта: роль shell_soft, но свой шейдер по имени меша
				m.shader = SKIRT_SHADER
			elif String(mi.name).ends_with("_glass"):
				m.shader = GLASS_SHADER
				m.set_shader_parameter("plate_size", mi.mesh.get_aabb().size.x)
			elif String(mi.name).ends_with("_mist"):
				m.shader = HAZE_SHADER
				if root.scene_file_path.contains("/room_edge_"):  # низкая дымка границы комнаты: профиль по высоте круче, штрихи по азимуту реже и слабее
					for k in EDGE_MIST:
						m.set_shader_parameter(k, EDGE_MIST[k])
			if String(mi.name) == "edge_streaks_hang":  # подвесные штрихи кромки комнаты (точек по периметру нет): ярче штрихов плит, иначе край не читается
				m.set_shader_parameter("glow", EDGE_STREAK_GLOW)
			if String(mi.name) == "pillar_block" or String(mi.name) == "pillar_base" or String(mi.name).begins_with("exit_bar"):  # укрытие (корпус и рамка по границе клетки) и брусья рамки выхода: рёбра ровные и яркие, иначе в очках не видно, где оно (у тайлов пола свет рваный намеренно)
				for k in PILLAR_EDGE:
					m.set_shader_parameter(k, PILLAR_EDGE[k])
			if tier != "" and TIER_TINT.has(tier):
				m.set_shader_parameter("tint", TIER_TINT[tier])
				m.set_shader_parameter("tint_amount", 1.0)
			if tier != "" and src.resource_name == "streaks":  # окружение: мягкий ореол и длинное затухание к концам; существа и аватары — резкие, без ореола
				var far := root.scene_file_path.contains("/far_")  # дальние пласты (8+ м): ореол вдвое-втрое расширяет квады, а видны они как дымка и без него
				m.set_shader_parameter("halo", 0.0 if far else ENV_HALO)
				m.set_shader_parameter("halo_width", ENV_HALO_WIDTH)
				m.set_shader_parameter("end_fade", ENV_END_FADE)
			if String(mi.name) == "beacon_halo":  # маяк предмета: капля свечения — свой шейдер; луч — streaks с ореолом (клиент выключает узел Beacon в руке)
				m.shader = BEACON_HALO_SHADER
			elif String(mi.name) == "beacon_beam":
				for k in BEACON_BEAM:
					m.set_shader_parameter(k, BEACON_BEAM[k])
			if entity and (src.resource_name == "streaks" or src.resource_name == "points"):
				m.set_shader_parameter("lattice", ENTITY_LATTICE)
			if String(mi.name).ends_with("_mid"):  # штрихи, симметричные вокруг центра (мембрана портала): длина меняется от центра
				m.set_shader_parameter("anchor", 0.0)
			if String(mi.name).ends_with("_hang"):  # подвесные штрихи (под полом): длина меняется от верхнего конца
				m.set_shader_parameter("anchor", 1.0)
			if FLOOR_V.has(fv):  # варианты пола: параметры по суффиксу меша, последними (поверх ореола и якоря)
				for suffix in FLOOR_V[fv]:
					if String(mi.name).ends_with(suffix):
						for k in FLOOR_V[fv][suffix]:
							m.set_shader_parameter(k, FLOOR_V[fv][suffix][k])
			mi.set_surface_override_material(s, m)


## Красный «шрам»: в радиусе вокруг точки (мировые координаты) свечение уходит в красный, часть клеток пропадает.
## Вызывать после apply(); radius = 0 выключает. Так ICE «ломает» соседнюю геометрию, а не рисует наклеенный эффект.
static func set_corruption(root: Node, world_pos: Vector3, radius: float) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m != null:
				m.set_shader_parameter("corrupt_pos", world_pos)
				m.set_shader_parameter("corrupt_radius", radius)


## Затухание по расстоянию до камеры (вместо depth-fade): дальние слои растворяются в темноте.
static func set_distance_fade(root: Node, start: float, end: float) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m != null:
				m.set_shader_parameter("fade_start", start)
				m.set_shader_parameter("fade_end", end)


## Общая яркость ассета (множитель): так делается отражение в полу (зеркальная копия с intensity ≈ 0.2).
static func set_intensity(root: Node, value: float) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m != null:
				m.set_shader_parameter("intensity", value)


## Параметр шейдера на всех материалах ассета (анимация и настройка из кода: touch_pos, touch_radius, breathe, pulse…).
static func set_param(root: Node, param: StringName, value: Variant) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m != null and m.shader.get_shader_uniform_list().any(func(u): return u["name"] == param):
				m.set_shader_parameter(param, value)
