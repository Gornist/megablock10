class_name LoadProbe
extends Node3D
## Синтетическая нагрузка для замеров на очках (`[render] probe = "quads=N,px=P,mode=blend|a2c|opaque|point"`, шаг П2 плана «волюметрик»):
## N одинаковых квадов (или точек) по P пикселей в поперечнике, приклеенных к голове, — кривая «мс кадра от (N, P)» без зависимости от позы и контента.
## Режимы V11: discard, points, points_a2c, gpup (см. MODES); `probe = "sweep_pts"` — серия SWEEP_PTS.
## `probe = "sweep"` — серия вариантов SWEEP одним запуском (ProbeSweep, без перезапусков игры между вариантами).
## Замер — как обычно: `bench` на ту же позу, один прогон с probe, один без; разница медиан = цена N квадов.
## Режимы: blend — альфа-смешение (как cloud на blend_add), a2c — alpha_to_coverage_and_one (как cloud_dark), opaque — без альфы (цена одной
## вершинной+растровой работы), point — PRIMITIVE_POINTS с point_size = P (цена без квадов).
## Шейдер собран строкой в коде: каталог assets/shaders — зона Blender, замерочный инструмент в неё не кладём.

## V11 (31.10, стайлгайд разд. 10): три способа рисовать одно и то же облако — discard (квады с отсечением по радиусу, MultiMesh), points / points_a2c
## (один ArrayMesh из N вершин PRIMITIVE_POINTS, POINT_SIZE = px), gpup (GPUParticles3D с постоянными позициями из текстуры); до 1 млн точек.
const MODES := ["blend", "a2c", "opaque", "point", "discard", "points", "points_a2c", "gpup"]
const DEFAULT_QUADS := 1000
const DEFAULT_PX := 16.0
const MAX_QUADS := 1000000
## Ширина текстуры позиций для gpup (высота = ceil(N / ширина)).
const POS_TEX_W := 1024
const MAX_PX := 512.0
## Серия для `probe = "sweep"`: первой идёт база без нагрузки (ProbeSweep), дальше по порядку.
const SWEEP := [
	"quads=2000,px=8,mode=blend", "quads=8000,px=8,mode=blend", "quads=32000,px=8,mode=blend",
	"quads=2000,px=16,mode=blend", "quads=8000,px=16,mode=blend", "quads=2000,px=32,mode=blend",
	"quads=2000,px=8,mode=a2c", "quads=8000,px=8,mode=a2c", "quads=32000,px=8,mode=a2c",
	"quads=2000,px=16,mode=a2c", "quads=8000,px=16,mode=a2c", "quads=2000,px=32,mode=a2c",
	"quads=8000,px=8,mode=opaque", "quads=8000,px=4,mode=point",
]
## Серия для `probe = "sweep_pts"` (V11): 5 способов × 100 тыс. / 300 тыс. / 1 млн, угловой размер точки 4 px. 15 вариантов + база,
## ≈ 16 × 13 с ≈ 3,5 мин (SETTLE 3 с + WINDOW 10 с на вариант); сборка 1 млн экземпляров удлиняет паузу между вариантами.
const SWEEP_PTS := [
	"quads=100000,px=4,mode=discard", "quads=300000,px=4,mode=discard", "quads=1000000,px=4,mode=discard",
	"quads=100000,px=4,mode=a2c", "quads=300000,px=4,mode=a2c", "quads=1000000,px=4,mode=a2c",
	"quads=100000,px=4,mode=points", "quads=300000,px=4,mode=points", "quads=1000000,px=4,mode=points",
	"quads=100000,px=4,mode=points_a2c", "quads=300000,px=4,mode=points_a2c", "quads=1000000,px=4,mode=points_a2c",
	"quads=100000,px=4,mode=gpup", "quads=300000,px=4,mode=gpup", "quads=1000000,px=4,mode=gpup",
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
	var out := {"on": false, "sweep": false, "sweep_name": "", "quads": DEFAULT_QUADS, "px": DEFAULT_PX, "mode": "blend", "warnings": PackedStringArray()}
	var s := spec.strip_edges().to_lower()
	if s == "" or s == "off":
		return out
	out["on"] = true
	if s == "sweep" or s == "sweep_pts":   # серия вариантов за один запуск (ProbeSweep)
		out["sweep"] = true
		out["sweep_name"] = s
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


## Шейдер V11-режимов: непрозрачно (кроме *_a2c), круглая форма — discard по радиусу (квады: UV, точки: POINT_COORD).
static func _v11_shader_code(probe_mode: String) -> String:
	var a2c := probe_mode == "points_a2c"
	var rm := "unshaded, depth_draw_opaque, cull_disabled, fog_disabled"
	if a2c:
		rm = "alpha_to_coverage_and_one, " + rm
	var code := "shader_type spatial;\nrender_mode %s;\nuniform float size = 0.03;\nuniform float point = 4.0;\nvarying vec2 uvq;\n" % rm
	code += "void vertex() {\n"
	if probe_mode.begins_with("points"):
		code += "\tPOINT_SIZE = point;\n"
	else:   # discard, gpup: квад-биллборд мирового размера
		code += "\tMODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);\n"
		code += "\tVERTEX *= size;\n"
	code += "\tuvq = UV * 2.0 - 1.0;\n}\n"
	code += "void fragment() {\n"
	if probe_mode.begins_with("points"):
		code += "\tfloat r = length(POINT_COORD * 2.0 - 1.0);\n"
	else:
		code += "\tfloat r = length(uvq);\n"
	if a2c:
		code += "\tALPHA = clamp(1.0 - r, 0.0, 1.0);\n"
	else:
		code += "\tif (r > 1.0) {\n\t\tdiscard;\n\t}\n"
	code += "\tALBEDO = vec3(0.1, 0.5, 0.6);\n}\n"
	return code


## Шейдер частиц gpup: позиция каждой частицы читается один раз в start() из текстуры RGBA32F шириной POS_TEX_W; process() пуст.
static func particles_shader_code() -> String:
	var code := "shader_type particles;\nuniform sampler2D pos_tex : filter_nearest;\n"
	code += "void start() {\n\tint w = %d;\n\tint i = int(INDEX);\n" % POS_TEX_W
	code += "\tTRANSFORM = mat4(1.0);\n\tTRANSFORM[3].xyz = texelFetch(pos_tex, ivec2(i % w, i / w), 0).xyz;\n}\n"
	code += "void process() {\n}\n"
	return code


## Текстура позиций для gpup: RGBAF, ширина POS_TEX_W, высота ceil(N / ширина); хвост добивается нулями.
static func positions_image(pts: PackedVector3Array) -> Image:
	var h := maxi(1, ceili(float(pts.size()) / POS_TEX_W))
	var data := PackedFloat32Array()
	data.resize(POS_TEX_W * h * 4)
	for i in pts.size():
		data[i * 4] = pts[i].x
		data[i * 4 + 1] = pts[i].y
		data[i * 4 + 2] = pts[i].z
		data[i * 4 + 3] = 1.0
	return Image.create_from_data(POS_TEX_W, h, false, Image.FORMAT_RGBAF, data.to_byte_array())


## Один ArrayMesh из N вершин PRIMITIVE_POINTS (не MultiMesh из одноточечных мешей — другая нагрузка).
static func points_mesh(pts: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	am.custom_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	return am


static func shader_code(probe_mode: String) -> String:
	if probe_mode in ["discard", "points", "points_a2c", "gpup"]:
		return _v11_shader_code(probe_mode)
	var rm :="unshaded, depth_draw_never, cull_disabled, fog_disabled"
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


## Строка `[probe] gpu adapter=… api=… renderer=… msaa=…`: по ней в журнале очков видно, какой GPU и работает ли Vulkan Mobile.
static func gpu_line(vp: Viewport) -> String:
	return "[probe] gpu adapter=%s api=%s renderer=%s msaa=%s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"), vp.msaa_3d if vp != null else "?"]


func _ready() -> void:
	print(gpu_line(get_viewport()))
	var shader := Shader.new()
	shader.code = shader_code(mode)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("size", quad_size(px))
	mat.set_shader_parameter("point", px)
	if mode == "points" or mode == "points_a2c":
		_build_points(mat)
		return
	if mode == "gpup":
		_build_gpup(mat)
		return
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
	# TRANSFORM_3D: 12 float на экземпляр (3 строки по 4: базис и origin) — одним буфером, а не 1 млн вызовов set_instance_transform.
	var buf := PackedFloat32Array()
	buf.resize(quads * 12)
	for i in quads:
		var o := i * 12
		buf[o] = 1.0
		buf[o + 3] = pts[i].x
		buf[o + 5] = 1.0
		buf[o + 7] = pts[i].y
		buf[o + 10] = 1.0
		buf[o + 11] = pts[i].z
	mm.buffer = buf
	mm.custom_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	_mm.extra_cull_margin = 16384.0
	add_child(_mm)


## points / points_a2c: один меш на N вершин, POINT_SIZE = px.
func _build_points(mat: ShaderMaterial) -> void:
	var mesh := points_mesh(positions(quads))
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.extra_cull_margin = 16384.0
	add_child(mi)


## gpup: GPUParticles3D, позиции один раз из текстуры в start(); приклеены к камере (local_coords), живут «вечно» одним выстрелом.
func _build_gpup(mat: ShaderMaterial) -> void:
	var pm := ShaderMaterial.new()
	var ps := Shader.new()
	ps.code = particles_shader_code()
	pm.shader = ps
	pm.set_shader_parameter("pos_tex", ImageTexture.create_from_image(positions_image(positions(quads))))
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	var gp := GPUParticles3D.new()
	gp.amount = quads
	gp.one_shot = true
	gp.explosiveness = 1.0
	gp.lifetime = 36000.0
	gp.local_coords = true
	gp.fixed_fps = 0
	gp.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	gp.process_material = pm
	gp.draw_pass_1 = q
	gp.emitting = true
	add_child(gp)
