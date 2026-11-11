extends Node3D
## Эталон вида Сети V11 (стайлгайд 31.10, сверка с киберпространством CP2077) — одна сцена на ПК, без ограничений по скорости:
## фойе 16×16 м, пол и 4 колонны 1,9×1,9×2,2 из точек строками скана, портал — видимый светящийся источник с ореолом,
## красная фигура. Без купола, неба, дымки, стен. Код клиента и AssetMaterials не трогает: всё своё в assets/look_v11/.
## Запуск: netrun/tools/dev.sh shot res://assets/look_v11/look_v11.tscn [--only=wide,pillar] [--set=row=0.04,pt=0.012,...]
## Ручки (--set): row, floor_row — шаг строк граней и пола (м); step — шаг точек в строке; pt — диаметр точки (м); min_px, min_row_px;
## fade_near, fade_far; gap — доля пропусков в строке; jit — разброс шага; light — сила подсветки от портала; halo — энергия ореола.

const VOID := Color("0a0c0e")
const WORLD_DIM := Color("1f3038")
const WORLD_LIT := Color("3f6068")
const CYAN := Color("28acae")
const CYAN_CORE := Color("76c6c5")
const RED := Color("c5384b")
const RED_DARK := Color("5a1a24")

const PILLARS := [Vector2(-3.2, -2.6), Vector2(3.2, -2.6), Vector2(-3.2, 2.4), Vector2(3.2, 2.4)]
const PILLAR_W := 1.9
const PILLAR_H := 2.2
const ROOM := 8.0
const PORTAL := Vector3(0.0, 0.0, -6.8)   # низ-центр портала
const PORTAL_W := 2.0
const PORTAL_H := 2.9
const FIGURE := Vector3(1.4, 0.0, -2.9)

var K := {
	"row": 0.035, "floor_row": 0.07, "step": 0.016, "pt": 0.007, "glow": 0.3, "glow_size": 3.0, "thick": 0.06, "thick_floor": 0.02, "occ_in": 0.3, "rag": 0.5, "rag_f": 1.1, "holes": 0.3, "wob": 0.8, "bulge": 0.35, "bulge_floor": 0.05, "stray": 0.03, "stray_d": 0.35, "world_rim": 2.5, "rjit": 0.15, "pvar": 0.6, "min_px": 1.6, "min_row_px": 5.0,
	"fade_near": 4.0, "fade_far": 20.0, "fade_min": 0.15, "light_r": 4.5, "gap": 0.05, "floor_step": 0.024, "flow_ang": 45.0, "flow_amp": 0.35, "flow_f": 1.2, "band": 0.2, "scatter": 0.08, "stroke": 0.09, "stroke_gap": 0.0, "flow_turn": 0.0, "jit": 0.6, "light": 4.0, "halo": 0.22, "sheet": 1.0,
	"edge": 0.6, "world_gain": 2.8, "fig": 1.0, "gap_len": 0.12, "clump_lo": 0.1, "clump_hi": 5.0, "clump_f": 0.3, "min_dot_px": 4.0,
}
var _out := "/tmp/look_v11"
var _only: Array = []
var _cam: Camera3D
var _halos: Array[MeshInstance3D] = []
var _seed := 1
var _shade := 0.7  # яркость текущей грани (к порталу ярче); пол сам тусклее граней
var _clump := FastNoiseLite.new()
var _thick_dir := Vector3.UP  # наружу от текущей поверхности
var _rag := FastNoiseLite.new()    # рваный край и дыры
var _wob := FastNoiseLite.new()    # волна строк
var _bulge := FastNoiseLite.new()  # вспучивание грани
var _flow := FastNoiseLite.new()   # изгиб волокон
## Запечённые точки (MultiMesh по имени набора) — для VR-демо: пишет --bake, читает look_vr.gd.
const BAKED_DIR := "res://assets/look_v11/baked"
var _have_baked := false
var _mms := {}


func _shots() -> Array:
	return [
		{"name": "wide", "cam": Vector3(2.0, 1.6, 7.2), "look": Vector3(-0.2, 1.0, -6.0), "fov": 60.0},
		{"name": "pillar", "cam": Vector3(0.9, 1.6, 4.2), "look": Vector3(2.6, 1.0, 2.2), "fov": 60.0},
		{"name": "floor", "cam": Vector3(-1.2, 1.6, 7.4), "look": Vector3(-0.3, 0.0, -1.5), "fov": 60.0},
	]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--only="):
			_only = Array(a.substr(7).split(","))
		elif a.begins_with("--set="):
			for kv in a.substr(6).split(","):
				var p := kv.split("=")
				if p.size() == 2 and K.has(p[0]):
					K[p[0]] = float(p[1])
	DirAccess.make_dir_recursive_absolute(_out)
	get_viewport().msaa_3d = Viewport.MSAA_4X  # эталон на ПК: гладкий край; на Pico — 2×
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = VOID
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_cam = Camera3D.new()
	_cam.far = 60.0
	add_child(_cam)
	var t0 := Time.get_ticks_msec()
	var n := _build()
	if "--bake" in OS.get_cmdline_user_args():  # запечь точки для VR-демо и выйти (pico_demo.sh)
		DirAccess.make_dir_recursive_absolute(BAKED_DIR)
		for nm: String in _mms:
			var err := ResourceSaver.save(_mms[nm], "%s/%s.res" % [BAKED_DIR, nm])
			print("LOOK bake %s: %s" % [nm, error_string(err)])
		get_tree().quit()
		return
	_cam.look_at_from_position(Vector3(0, 1.6, 6), Vector3(0, 1, 0))
	await get_tree().create_timer(2.0).timeout  # прогрев: шейдеры компилируются, первый кадр иначе пустой
	print("LOOK points=%d build=%d ms" % [n, Time.get_ticks_msec() - t0])
	for shot in _shots():
		if not _only.is_empty() and not (shot["name"] in _only):
			continue
		_cam.fov = shot["fov"]
		_cam.look_at_from_position(shot["cam"], shot["look"])
		for hl in _halos:
			hl.look_at(_cam.global_position, Vector3.UP)
			hl.rotate_object_local(Vector3.UP, PI)
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_out, shot["name"]])
		print("SHOT ", shot["name"], " ", img.get_size())
	get_tree().quit()


# --- генерация ---------------------------------------------------------------------------------------------

var _buf := PackedFloat32Array()
var _cnt := 0


func _rand() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_seed) / 2147483647.0


static func _h(i: float) -> float:
	var x := sin(i * 12.9898) * 43758.5453
	return x - floorf(x)


static func _noise1(x: float, s: float) -> float:  # гладкий шум по строке: пропуски кусками, а не крошкой
	var i := floorf(x)
	var f := x - i
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(_h(i + s * 17.31), _h(i + 1.0 + s * 17.31), f)


func _portal_light(p: Vector3) -> float:
	var c := PORTAL + Vector3(0.0, PORTAL_H * 0.5, 0.25)
	var d := p.distance_to(c)
	return _k("light") / (1.0 + pow(d / _k("light_r"), 2.0))


## Экземпляр: базис X — нормаль (для фигуры), начало — центр точки; COLOR.a — случайный порог прореживания в строке.
func _push(p: Vector3, col: Color, row: int, row_step: float, kind: float, size: float, nrm := Vector3.RIGHT) -> void:
	_buf.append_array([nrm.x, 0.0, 0.0, p.x, nrm.y, 1.0, 0.0, p.y, nrm.z, 0.0, 1.0, p.z,
		col.r, col.g, col.b, _rand(), float(row), row_step, kind, size])
	_cnt += 1


## Цвет точки мира — по рампе яркости, а не умножением: тусклые — стальная бирюза #1F3038, светлые уходят в насыщенную
## #3F6068 и выше к циану (умножение серо-бирюзового цвета давало белёсые точки — у CP2077 светлые точки синее, а не белее).
const WORLD_RAMP := [Color("0e161a"), Color("1f3038"), Color("3f6068"), Color("4a8a9a"), Color("6fb4bb")]


func _world_col(p: Vector3, edge_k: float) -> Color:
	var l := _portal_light(p)
	# сгустки: медленный шум по поверхности — где-то строки ярче, где-то почти гаснут (у CP2077 поверхность неровная по яркости)
	# шум вытянут по диагонали — светлые полосы-разводы, как на камнях CP2077, а не круглые пятна
	var q := Vector3(p.x * 0.6 + p.y * 1.2, p.y * 0.35, p.z * 0.6 - p.y * 1.2)
	var cl := 0.5 + 0.5 * _clump.get_noise_3dv(q)
	var v := (1.0 + _k("pvar") * (_rand() - 0.5)) * lerpf(_k("clump_lo"), _k("clump_hi"), cl * cl) * _shade * (0.08 + 0.92 * edge_k)
	v = v * _k("world_gain") * 0.33 + l * (0.6 + 0.6 * _rand())  # 1.0 ≈ #1F3038; свет портала сверху
	var x := clampf(v, 0.0, 3.999)
	var i := int(x)
	var c: Color = (WORLD_RAMP[i] as Color).lerp(WORLD_RAMP[i + 1], x - float(i))
	return c.srgb_to_linear()




## Лист точек на прямоугольнике o + ud·u + vd·v (u ∈ [0, w], v ∈ [0, h]) — волокнами вдоль формы, а не горизонтальными строками
## (владелец 31.10: «всё из горизонтальных линий, в CP2077 не так»). Волокно — изолиния поля f = v·cos A + u·sin A + шум:
## у каждой грани свой наклон A, шум изгибает волокна, так что они текут косо и дугами. Точка берётся, если лежит у изолинии
## (|f/шаг − целое| < band); доля scatter — россыпью между волокнами. keep(t, p) — вероятность и яркость края (t — доля по u).
func _sheet(o: Vector3, ud: Vector3, vd: Vector3, w: float, h: float, kind: float, keep: Callable, sd: float) -> void:
	if _have_baked:  # точки уже запечены (VR-демо): генерация на очках шла бы десятки секунд
		return
	var st: float = _k("step") if kind < 0.5 else _k("floor_step")
	var rs: float = _k("row") if kind < 0.5 else _k("floor_row")
	var ang := deg_to_rad(_k("flow_ang")) * (_h(sd * 3.7 + 1.0) * 2.0 - 1.0)
	var ca := cos(ang)
	var sa := sin(ang)
	var amp: float = _k("flow_amp")
	var fq: float = _k("flow_f")
	var band: float = _k("band")
	var jit: float = _k("jit")
	var v := _rand() * st
	while v < h:
		var u := _rand() * st
		while u < w:
			var uu := u + (_rand() - 0.5) * st * jit
			var vv := v + (_rand() - 0.5) * st * jit
			u += st
			# направление штриховки плавно поворачивается по грани (веером), как волокна по изгибу камня
			var a2 := ang + deg_to_rad(_k("flow_turn")) * _flow.get_noise_2d(uu * 0.3 + sd * 3.1, vv * 0.3 - sd)
			ca = cos(a2)
			sa = sin(a2)
			var f := vv * ca + uu * sa + amp * _flow.get_noise_2d(uu * fq + sd * 7.31, vv * fq)
			var rf := f / rs
			var ri := floorf(rf + 0.5)
			var scatter := _rand() < _k("scatter")
			if absf(rf - ri) > band and not scatter:
				continue
			# волокно рвётся на короткие штрихи (у CP2077 — штриховка вдоль формы, а не бесконечные линии)
			var seg := floorf((uu * ca - vv * sa) / _k("stroke"))
			if not scatter and _h(ri * 13.1 + seg * 7.7 + sd) < _k("stroke_gap"):
				continue
			if _rand() < _k("gap"):
				continue
			_emit(o + ud * uu + vd * vv, uu / w, int(absf(ri)), rs, kind, keep, scatter)
		v += st


## Одна точка оболочки: вспучивание, дыры, толщина, пыль, прореживание по краю, цвет.
func _emit(p: Vector3, t: float, row: int, row_step: float, kind: float, keep: Callable, scatter: bool) -> void:
	# грань вспучена — медленный шум выдавливает оболочку наружу (только наружу: внутрь ушло бы за тело колонны);
	var bl := 0.5 + 0.5 * _bulge.get_noise_3dv(p)
	p += _thick_dir * bl * bl * (_k("bulge") if kind < 0.5 else _k("bulge_floor"))
	# дыры — рваные куски оболочки выпадают целиком;
	var hn := _rag.get_noise_3dv(p * 0.6)
	if _rand() < smoothstep(_k("holes"), _k("holes") + 0.12, hn):
		return
	# толщина: точки лежат слоем наружу (чаще у поверхности) — объём, а не плёнка; редкие отлетают дальше — пыль у поверхности.
	var th := _rand()
	p += _thick_dir * th * th * (_k("thick") if kind < 0.5 else _k("thick_floor"))
	var stray := _rand() < _k("stray")
	if stray:
		p += _thick_dir * _rand() * _k("stray_d") + Vector3(_rand() - 0.5, (_rand() - 0.5) * 0.5, _rand() - 0.5) * _k("stray_d") * 0.5
	var ke: Vector2 = keep.call(t, p)
	var lp := _portal_light(p)
	if _rand() > clampf(ke.x * (1.0 + lp * 0.6), 0.0, 1.0):
		return
	var sz: float = _k("pt") * (0.8 + 0.4 * _rand())
	_push(p, _world_col(p, ke.y * (0.45 if stray else (0.6 if scatter else 1.0))), row, row_step, kind, sz, _thick_dir)


func _build() -> int:
	_buf = PackedFloat32Array()
	_cnt = 0
	_clump.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_clump.frequency = _k("clump_f")
	_clump.seed = 7
	_clump.fractal_octaves = 3
	for nz: FastNoiseLite in [_rag, _wob, _bulge, _flow]:
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	_rag.frequency = _k("rag_f")
	_rag.fractal_octaves = 4
	_rag.seed = 11
	_wob.frequency = 0.9
	_wob.fractal_octaves = 2
	_wob.seed = 13
	_bulge.frequency = 0.7
	_bulge.fractal_octaves = 2
	_bulge.seed = 17
	_flow.frequency = 1.0
	_flow.fractal_octaves = 3
	_flow.seed = 23
	var edge: float = _k("edge")
	# Пол: волокна точек (не строки по линейке); растушёвка к краю комнаты и у оснований колонн.
	var keep_floor := func(_t: float, p: Vector3) -> Vector2:
		var rg := _rag.get_noise_3dv(p * 0.9) * _k("rag")
		var e := minf(ROOM - absf(p.x), ROOM - absf(p.z)) + rg * 4.0
		var k := smoothstep(0.0, 2.5, e)
		for pc in PILLARS:
			var dx := absf(p.x - pc.x) - PILLAR_W * 0.5
			var dz := absf(p.z - pc.y) - PILLAR_W * 0.5
			var dd := maxf(dx, dz)
			if dd < 0.03:
				return Vector2(0.0, 0.0)
			k *= 0.35 + 0.65 * smoothstep(0.0, 0.6, dd + rg)
		return Vector2(0.15 + 0.85 * k, k)
	_sheet(Vector3(-ROOM, 0.0, -ROOM), Vector3.RIGHT, Vector3.BACK, 2.0 * ROOM, 2.0 * ROOM, 1.0, keep_floor, 0.5)
	# Колонны: 4 грани, у каждой свой наклон волокон; край растворяется к рёбрам, низу и верху.
	var hw := PILLAR_W * 0.5 + 0.012
	for pi in PILLARS.size():
		var pc: Vector2 = PILLARS[pi]
		var corners := [Vector3(pc.x - hw, 0, pc.y - hw), Vector3(pc.x + hw, 0, pc.y - hw), Vector3(pc.x + hw, 0, pc.y + hw), Vector3(pc.x - hw, 0, pc.y + hw)]
		for f in 4:
			var a: Vector3 = corners[f]
			var b: Vector3 = corners[(f + 1) % 4]
			var nrm := Vector3.UP.cross(b - a).normalized()  # наружу
			_thick_dir = nrm
			var to_p := (PORTAL + Vector3(0, PORTAL_H * 0.5, 0) - (a + b) * 0.5).normalized()
			_shade = 0.5 + 0.7 * maxf(0.0, nrm.dot(to_p)) + 0.2 * absf(nrm.x)
			var keep := func(t: float, p: Vector3) -> Vector2:
				var y := p.y
				# рваный край: расстояние до ребра/верха/низа сдвинуто шумом — граница оболочки неровная, с языками и выгрызами
				var rg := _rag.get_noise_3dv(p * 1.7) * _k("rag")
				var es := minf(t, 1.0 - t) * PILLAR_W + rg
				var k := smoothstep(0.0, edge, es) * smoothstep(0.0, edge * 0.8, PILLAR_H - y + rg) * (0.3 + 0.7 * smoothstep(0.0, edge * 1.2, y + rg))
				return Vector2(0.04 + 0.96 * k, k)
			_sheet(a, (b - a).normalized(), Vector3.UP, a.distance_to(b), PILLAR_H, 0.0, keep, float(pi * 4 + f) + 1.0)
	_shade = 1.0
	var world_n := _cnt
	_add_points("World", _buf, world_n, {"pt_step": _k("step"), "min_dot_px": _k("min_dot_px"), "world_rim": _k("world_rim")})
	_add_occluders()
	# Портал: рама из ярких точек строками, световой лист с потёками, ореол.
	_buf = PackedFloat32Array()
	_cnt = 0
	var pr := 0.03
	for r in int(PORTAL_H / pr) + 1:
		var y := r * pr
		for side in [-1.0, 1.0]:
			for j in 3:
				var p := PORTAL + Vector3(side * (PORTAL_W * 0.5 + 0.03 + j * 0.035), y, 0.0)
				var c := CYAN.lerp(CYAN_CORE, 0.5 * _rand() + (0.4 if j == 0 else 0.0))
				if _rand() < 0.85:
					_push(p, c.srgb_to_linear(), r, pr, 3.0, 0.02)
	for i in int(PORTAL_W / 0.025):
		for j in 3:
			var p := PORTAL + Vector3(-PORTAL_W * 0.5 + i * 0.025, PORTAL_H + 0.03 + j * 0.035, 0.0)
			if _rand() < 0.85:
				_push(p, CYAN.lerp(CYAN_CORE, 0.6 * _rand()).srgb_to_linear(), 0, pr, 3.0, 0.02)
	_add_points("PortalFrame", _buf, _cnt, {"fade_min": 0.85, "fade_far": 30.0})
	var sheet := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(PORTAL_W, PORTAL_H)
	sheet.mesh = q
	sheet.position = PORTAL + Vector3(0, PORTAL_H * 0.5, 0)
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://assets/look_v11/glow.gdshader")
	sm.set_shader_parameter("mode", 1)
	sm.set_shader_parameter("energy", _k("sheet"))
	sheet.material_override = sm
	add_child(sheet)
	_add_halo(PORTAL + Vector3(0, PORTAL_H * 0.5, 0.15), Vector2(PORTAL_W * 3.2, PORTAL_H * 2.0), _k("halo"))
	_add_figure(FIGURE)
	return world_n + _cnt


func _add_points(nm: String, buf: PackedFloat32Array, n: int, params: Dictionary) -> void:
	var mm: MultiMesh
	var bp := "%s/%s.res" % [BAKED_DIR, nm]
	if _have_baked and ResourceLoader.exists(bp):
		mm = load(bp) as MultiMesh
	else:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		mm.mesh = q
		mm.instance_count = n
		mm.buffer = buf
	_mms[nm] = mm
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 15, 40))
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/look_v11/scan_point.gdshader")
	m.set_shader_parameter("vp_h", _vp_h())
	for key in ["min_px", "min_row_px", "fade_near", "fade_far", "fade_min"]:
		m.set_shader_parameter(key, K[key])
	for key in params:
		m.set_shader_parameter(key, params[key])
	mi.material_override = m
	add_child(mi)
	if _k("glow") <= 0.0:
		return
	# Ореол точки: тот же MultiMesh вторым проходом — квад крупнее, мягкое пятно аддитивно. Точка светится, а не лежит краской на грани.
	var gi := MultiMeshInstance3D.new()
	gi.name = nm + "Glow"
	gi.multimesh = mm
	gi.custom_aabb = mi.custom_aabb
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://assets/look_v11/scan_glow.gdshader")
	for key in ["min_px", "min_row_px", "fade_near", "fade_far", "fade_min"]:
		gm.set_shader_parameter(key, K[key])
	for key in params:
		gm.set_shader_parameter(key, params[key])
	gm.set_shader_parameter("vp_h", _vp_h())
	gm.set_shader_parameter("size_mul", _k("glow_size"))
	gm.set_shader_parameter("glow", _k("glow"))
	gi.material_override = gm
	add_child(gi)


## Непрозрачность граней (решение 19.10): тело колонны цвета пустоты пишет глубину — сквозь колонну не видно, что за ней.
func _add_occluders() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = VOID
	for pc in PILLARS:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(PILLAR_W - _k("occ_in") * 2.0, PILLAR_H - _k("occ_in"), PILLAR_W - _k("occ_in") * 2.0)  # тело меньше оболочки: ребро растворяется в пустоту, а не обрывается силуэтом
		b.mesh = bm
		b.material_override = m
		b.position = Vector3(pc.x, (PILLAR_H - _k("occ_in")) * 0.5, pc.y)
		add_child(b)


func _add_halo(pos: Vector3, size: Vector2, energy: float) -> void:
	var hl := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	hl.mesh = q
	hl.position = pos
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/look_v11/glow.gdshader")
	m.set_shader_parameter("mode", 0)
	m.set_shader_parameter("energy", energy)
	hl.material_override = m
	add_child(hl)
	_halos.append(hl)


## Фигура человека из капсул (рост ≈1,75 м, лицом к +Z): оболочка из красных точек строками по высоте, нормаль точки — в базисе
## экземпляра (шейдер светлит кромку по френелю), внутри — тело цвета пустоты (непрозрачна); к кромке точки редеют — край рассыпается.
const FIG_PARTS := [  # [радиус, высота, центр, наклон по Z (°)]
	[0.075, 0.48, Vector3(-0.1, 0.25, 0), 2.0], [0.075, 0.48, Vector3(0.1, 0.25, 0), -2.0],      # голени
	[0.09, 0.5, Vector3(-0.1, 0.68, 0), 3.0], [0.09, 0.5, Vector3(0.1, 0.68, 0), -3.0],          # бёдра
	[0.16, 0.34, Vector3(0, 0.98, 0), 0.0],                                                      # таз
	[0.15, 0.5, Vector3(0, 1.22, 0), 0.0],                                                       # торс
	[0.075, 0.5, Vector3(0, 1.4, 0), 90.0],                                                      # плечи
	[0.05, 0.36, Vector3(-0.27, 1.22, 0.0), -12.0], [0.05, 0.36, Vector3(0.27, 1.22, 0.0), 12.0],  # плечо руки
	[0.042, 0.36, Vector3(-0.32, 0.92, 0.04), -4.0], [0.042, 0.36, Vector3(0.32, 0.92, 0.04), 4.0],  # предплечья
	[0.05, 0.14, Vector3(0, 1.52, 0), 0.0],                                                      # шея
	[0.1, 0.25, Vector3(0, 1.65, 0.01), 0.0],                                                    # голова
]


func _add_figure(base: Vector3) -> void:
	var root := Node3D.new()
	root.position = base
	root.rotation.y = deg_to_rad(-25.0)
	add_child(root)
	var occ := StandardMaterial3D.new()
	occ.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	occ.albedo_color = VOID
	_buf = PackedFloat32Array()
	_cnt = 0
	var rs := 0.016
	var dark := RED_DARK.lerp(RED, 0.35).srgb_to_linear()  # тело светится само: тусклый малиновый, кромка — ядро
	for pt in FIG_PARTS:
		var r: float = pt[0]
		var hgt: float = pt[1]
		var xf := root.transform * Transform3D(Basis(Vector3.BACK, deg_to_rad(pt[3])), pt[2])
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = r - 0.006
		cm.height = hgt - 0.012
		mi.mesh = cm
		mi.transform = xf
		mi.material_override = occ
		add_child(mi)
		var half := hgt * 0.5 - r
		var y := -hgt * 0.5 + rs * 0.5
		while y < hgt * 0.5:
			var cy := clampf(y, -half, half)
			var rad := sqrt(maxf(r * r - (y - cy) * (y - cy), 0.0))
			var n := int(TAU * rad / 0.015)
			for i in n:
				var a := (float(i) + _rand() * 0.6) / float(maxi(n, 1)) * TAU
				var lp := Vector3(cos(a) * rad, y, sin(a) * rad)
				var nrm := xf.basis * (lp - Vector3(0, cy, 0)).normalized()
				var b := (0.35 + 1.3 * _rand() * _rand() * 1.6) * _k("fig")
				_push(xf * lp, Color(dark.r * b, dark.g * b, dark.b * b), 0, rs, 3.0, 0.0075, nrm)
			y += rs
	_add_points("Figure", _buf, _cnt, {"rim_gain": 1.4 * _k("fig"), "rim_col": RED, "fade_min": 0.6})


## Высота кадра, px, для перевода мирового размера точки в экранный (в VR — высота кадра глаза).
func _vp_h() -> float:
	return float(get_viewport().get_visible_rect().size.y)


func _k(n: String) -> float:
	return float(K[n])
