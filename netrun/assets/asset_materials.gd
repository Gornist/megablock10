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

## Цвета тиров окружения (BASE/HARD/NIGHTMARE): голубая гамма, красный в тирах не участвует.
const TIER_TINT := {
	"BASE": Color("18e6ff"),
	"HARD": Color("2a7bff"),
	"NIGHTMARE": Color("8a5cff"),
}


## tier — "BASE"/"HARD"/"NIGHTMARE" для окружения (перекрашивает свечение); пусто — цвета из вершин (ICE, аватар, дека).
static func apply(root: Node, tier: String = "") -> void:
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
			if tier != "" and TIER_TINT.has(tier):
				m.set_shader_parameter("tint", TIER_TINT[tier])
				m.set_shader_parameter("tint_amount", 1.0)
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
