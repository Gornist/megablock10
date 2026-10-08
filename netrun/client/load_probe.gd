class_name LoadProbe
extends Node3D
## Синтетическая нагрузка для замеров на очках (`[render] probe = "quads=N,px=P,mode=blend|a2c|opaque|point"`, шаг П2 плана «волюметрик»):
## N одинаковых квадов (или точек) по P пикселей в поперечнике, приклеенных к голове, — кривая «мс кадра от (N, P)» без зависимости от позы и контента.
## `probe = "sweep"` — серия вариантов SWEEP одним запуском (ProbeSweep, без перезапусков игры между вариантами).
## Замер — как обычно: `bench` на ту же позу, один прогон с probe, один без; разница медиан = цена N квадов.
## Режимы: blend — альфа-смешение (как cloud на blend_add), a2c — alpha_to_coverage_and_one (как cloud_dark), opaque — без альфы (цена одной
## вершинной+растровой работы), point — PRIMITIVE_POINTS с point_size = P (цена без квадов).
## Шейдер собран строкой в коде: каталог assets/shaders — зона Blender, замерочный инструмент в неё не кладём.

const MODES := ["blend", "a2c", "opaque", "point"]
const DEFAULT_QUADS := 1000
const DEFAULT_PX := 16.0
const MAX_QUADS := 200000
const MAX_PX := 512.0
## Серия для `probe = "sweep"`: первой идёт база без нагрузки (ProbeSweep), дальше по порядку.
const SWEEP := [
	"quads=2000,px=8,mode=blend", "quads=8000,px=8,mode=blend", "quads=32000,px=8,mode=blend",
	"quads=2000,px=16,mode=blend", "quads=8000,px=16,mode=blend", "quads=2000,px=32,mode=blend",
	"quads=2000,px=8,mode=a2c", "quads=8000,px=8,mode=a2c", "quads=32000,px=8,mode=a2c",
	"quads=2000,px=16,mode=a2c", "quads=8000,px=16,mode=a2c", "quads=2000,px=32,mode=a2c",
	"quads=8000,px=8,mode=opaque", "quads=8000,px=4,mode=point",
]
## Расстояние от головы, на котором расставлены кванты, м.
const DISTANCE := 2.5
## Угловой размер пикселя Pico 4 (≈100° на 1504 px), рад.
const RAD_PER_PX := 0.00116
## Половина угла раствора облака квадов перед лицом (вдоль и поперёк), рад.
const HALF_ANGLE := 0.7

var quads := DEFAULT_QUADS
var px := DEFAULT_PX
var mode := "blend"

var _mm: MultiMeshInstance3D


## Разбор строки «quads=N,px=P,mode=M» (любой порядок, пропуски — по умолчанию). Неверное поле — в warnings, пустая строка — выкл. (spec["on"] = false).
static func parse(spec: String) -> Dictionary:
	var out := {"on": false, "sweep": false, "quads": DEFAULT_QUADS, "px": DEFAULT_PX, "mode": "blend", "warnings": PackedStringArray()}
	var s := spec.strip_edges().to_lower()
	if s == "" or s == "off":
		return out
	out["on"] = true
	if s == "sweep":   # серия вариантов за один запуск (ProbeSweep)
		out["sweep"] = true
		return out
	for part in s.split(","):
		var kv := part.strip_edges().split("=")
		if kv.size() != 2:
			out["warnings"].append("probe: часть «%s» не вида ключ=значение — пропущена" % part)
			continue
		var k := kv[0].strip_edges()
		var v := kv[1].strip_edges()
		match k:
			"quads":
				if v.is_valid_int() and v.to_int() >= 1 and v.to_int() <= MAX_QUADS:
					out["quads"] = v.to_int()
				else:
					out["warnings"].append("probe: quads — целое 1…%d, получено «%s»" % [MAX_QUADS, v])
			"px":
				if v.is_valid_float() and v.to_float() >= 1.0 and v.to_float() <= MAX_PX:
					out["px"] = v.to_float()
				else:
					out["warnings"].append("probe: px — число 1…%d, получено «%s»" % [int(MAX_PX), v])
			"mode":
				if v in MODES:
					out["mode"] = v
				else:
					out["warnings"].append("probe: mode — одно из %s, получено «%s»" % [", ".join(MODES), v])
			_:
				out["warnings"].append("probe: неизвестный ключ «%s» — пропущен" % k)
	return out


## Сторона квада в метрах на расстоянии distance, чтобы он занимал px пикселей.
static func quad_size(px_count: float, distance: float = DISTANCE) -> float:
	return px_count * RAD_PER_PX * distance


## Детерминированные позиции N точек в пирамиде взгляда (локально камере: −Z вперёд), на расстоянии DISTANCE (с небольшим разбросом глубины).
static func positions(count: int) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261008
	var out := PackedVector3Array()
	out.resize(count)
	for i in count:
		var ax := rng.randf_range(-HALF_ANGLE, HALF_ANGLE)
		var ay := rng.randf_range(-HALF_ANGLE, HALF_ANGLE)
		var d := DISTANCE * rng.randf_range(0.8, 1.2)
		out[i] = Vector3(tan(ax) * d, tan(ay) * d, -d)
	return out


static func shader_code(probe_mode: String) -> String:
	var rm := "unshaded, depth_draw_never, cull_disabled, fog_disabled"
	match probe_mode:
		"blend":
			rm = "blend_add, " + rm
		"a2c":
			rm = "alpha_to_coverage_and_one, " + rm
		"point":
			rm = "blend_add, " + rm
	var code := "shader_type spatial;\nrender_mode %s;\nuniform float size = 0.03;\nuniform float point = 16.0;\nvarying vec2 uvq;\n" % rm
	code += "void vertex() {\n"
	if probe_mode == "point":
		code += "\tPOINT_SIZE = point;\n"
	else:
		code += "\tMODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);\n"
		code += "\tVERTEX *= size;\n"   # QuadMesh размера 1 → сторона size
	code += "\tuvq = UV * 2.0 - 1.0;\n}\n"
	code += "void fragment() {\n\tfloat r = length(uvq);\n"
	match probe_mode:
		"opaque":
			code += "\tALBEDO = vec3(0.1, 0.5, 0.6);\n"
		"point":
			code += "\tALBEDO = vec3(0.1, 0.5, 0.6) * 0.05;\n"
		_:
			code += "\tALBEDO = vec3(0.1, 0.5, 0.6) * 0.05;\n\tALPHA = clamp(1.0 - r, 0.0, 1.0);\n"
	code += "}\n"
	return code


func setup(spec: Dictionary) -> void:
	quads = spec["quads"]
	px = spec["px"]
	mode = spec["mode"]


func _ready() -> void:
	var shader := Shader.new()
	shader.code = shader_code(mode)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("size", quad_size(px))
	mat.set_shader_parameter("point", px)
	var mesh: Mesh
	if mode == "point":
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO])
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
		mesh = am
	else:
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		mesh = q
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = quads
	var pts := positions(quads)
	for i in quads:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i]))
	mm.custom_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	_mm.extra_cull_margin = 16384.0
	add_child(_mm)
