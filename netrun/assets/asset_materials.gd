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
## ЭКСПЕРИМЕНТ: верх стеклянного пола (меш `*_glass` в env/floor_glass_<N>): роль shell_soft, шейдер по имени меша; сторону плиты (plate_size) берём из AABB меша.
const GLASS_SHADER := preload("res://assets/shaders/glass.gdshader")

## Параметры haze.gdshader для `edge_mist` (env/room_edge_<N>): низкая дымка вдоль границы комнаты, не туман горизонта.
const EDGE_MIST := {"haze_alpha": 0.6, "glow": 1.6, "shape": 1.0, "noise_amount": 0.35, "stripe_amount": 0.12, "stripe_count": 160.0}

## Яркость подвесных штрихов кромки комнаты (`edge_streaks_hang`): у штрихов окружения glow 1,6.
const EDGE_STREAK_GLOW := 2.6

## Цвета тиров окружения (BASE/HARD/NIGHTMARE): голубая гамма, красный в тирах не участвует.
const TIER_TINT := {
	"BASE": Color("18e6ff"),
	"HARD": Color("2a7bff"),
	"NIGHTMARE": Color("8a5cff"),
}

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
static func apply(root: Node, tier: String = "") -> void:
	var entity := _is_entity(root)
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
			if tier != "" and TIER_TINT.has(tier):
				m.set_shader_parameter("tint", TIER_TINT[tier])
				m.set_shader_parameter("tint_amount", 1.0)
			if tier != "" and src.resource_name == "streaks":  # окружение: мягкий ореол и длинное затухание к концам; существа и аватары — резкие, без ореола
				m.set_shader_parameter("halo", ENV_HALO)
				m.set_shader_parameter("halo_width", ENV_HALO_WIDTH)
				m.set_shader_parameter("end_fade", ENV_END_FADE)
			if entity and (src.resource_name == "streaks" or src.resource_name == "points"):
				m.set_shader_parameter("lattice", ENTITY_LATTICE)
			if String(mi.name).ends_with("_mid"):  # штрихи, симметричные вокруг центра (мембрана портала): длина меняется от центра
				m.set_shader_parameter("anchor", 0.0)
			if String(mi.name).ends_with("_hang"):  # подвесные штрихи (под полом): длина меняется от верхнего конца
				m.set_shader_parameter("anchor", 1.0)
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
