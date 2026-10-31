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
const PORTAL_W := 1.3
const PORTAL_H := 2.3
const FIGURE := Vector3(1.4, 0.0, -2.9)

var K := {
	"row": 0.028, "floor_row": 0.05, "step": 0.011, "pt": 0.0075, "rjit": 0.3, "pvar": 1.1, "min_px": 1.6, "min_row_px": 3.0,
	"fade_near": 4.0, "fade_far": 20.0, "fade_min": 0.15, "light_r": 4.5, "gap": 0.12, "jit": 0.6, "light": 4.0, "halo": 0.22, "sheet": 1.0,
	"edge": 0.6, "world_gain": 3.6, "fig": 1.0, "gap_len": 0.12, "clump_lo": 0.1, "clump_hi": 5.0, "clump_f": 0.6, "min_dot_px": 2.6,
}
var _out := "/tmp/look_v11"
var _only: Array = []
var _cam: Camera3D
var _halos: Array[MeshInstance3D] = []
var _seed := 1
var _shade := 0.7  # яркость текущей грани (к порталу ярче); пол сам тусклее граней
var _clump := FastNoiseLite.new()


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
	var cl := 0.5 + 0.5 * _clump.get_noise_3dv(p)
	var v := (1.0 + _k("pvar") * (_rand() - 0.5)) * lerpf(_k("clump_lo"), _k("clump_hi"), cl * cl) * _shade * (0.3 + 0.7 * edge_k)
	v = v * _k("world_gain") * 0.33 + l * (0.6 + 0.6 * _rand())  # 1.0 ≈ #1F3038; свет портала сверху
	var x := clampf(v, 0.0, 3.999)
	var i := int(x)
	var c: Color = (WORLD_RAMP[i] as Color).lerp(WORLD_RAMP[i + 1], x - float(i))
	return c.srgb_to_linear()


## Строка точек вдоль отрезка a→b (горизонтальная): шаг с разбросом, пропуски кусками по шуму; keep(t, p) — вероятность, edge(t, p) — яркость края.
func _row(a: Vector3, b: Vector3, row: int, row_step: float, kind: float, keep: Callable, rs: float) -> void:
	var ln := a.distance_to(b)
	var dir := (b - a) / ln
	var x := _rand() * _k("step")
	var gap: float = _k("gap")
	while x < ln:
		var p := a + dir * x + (Vector3.UP if kind < 0.5 else Vector3.BACK) * (_rand() - 0.5) * _k("rjit") * row_step
		var t := x / ln
		x += _k("step") * (1.0 + _k("jit") * (_rand() - 0.5) * 2.0)
		if _noise1(x / _k("gap_len"), rs) < gap:
			continue
		var ke: Vector2 = keep.call(t, p)
		var lp := _portal_light(p)
		if _rand() > clampf(ke.x * (1.0 + lp * 0.6), 0.0, 1.0):
			continue
		var sz: float = _k("pt") * (0.8 + 0.4 * _rand())
		_push(p, _world_col(p, ke.y), row, row_step, kind, sz)


func _build() -> int:
	_buf = PackedFloat32Array()
	_cnt = 0
	_clump.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_clump.frequency = _k("clump_f")
	_clump.seed = 7
	var edge: float = _k("edge")
	# Пол: строки вдоль X, шаг по Z; растушёвка к краю комнаты и у оснований колонн.
	var fr: float = _k("floor_row")
	var nrows := int(2.0 * ROOM / fr)
	for r in nrows:
		var z := -ROOM + (r + 0.5) * fr
		var keep := func(_t: float, p: Vector3) -> Vector2:
			var e := minf(ROOM - absf(p.x), ROOM - absf(p.z))
			var k := smoothstep(0.0, 2.5, e)
			for pc in PILLARS:
				var dx := absf(p.x - pc.x) - PILLAR_W * 0.5
				var dz := absf(p.z - pc.y) - PILLAR_W * 0.5
				var dd := maxf(dx, dz)
				if dd < 0.03:
					return Vector2(0.0, 0.0)
				k *= 0.35 + 0.65 * smoothstep(0.0, 0.6, dd)
			return Vector2(0.15 + 0.85 * k, k)
		_row(Vector3(-ROOM, 0.0, z), Vector3(ROOM, 0.0, z), r, fr, 1.0, keep, float(r) + 0.5)
	# Колонны: 4 грани, строки по высоте; край растворяется к рёбрам, низу и верху.
	var rs: float = _k("row")
	var hrows := int(PILLAR_H / rs)
	var hw := PILLAR_W * 0.5 + 0.012
	for pi in PILLARS.size():
		var pc: Vector2 = PILLARS[pi]
		var corners := [Vector3(pc.x - hw, 0, pc.y - hw), Vector3(pc.x + hw, 0, pc.y - hw), Vector3(pc.x + hw, 0, pc.y + hw), Vector3(pc.x - hw, 0, pc.y + hw)]
		for f in 4:
			var a: Vector3 = corners[f]
			var b: Vector3 = corners[(f + 1) % 4]
			var nrm := (b - a).cross(Vector3.UP).normalized()
			var to_p := (PORTAL + Vector3(0, PORTAL_H * 0.5, 0) - (a + b) * 0.5).normalized()
			_shade = 0.5 + 0.7 * maxf(0.0, nrm.dot(to_p)) + 0.2 * absf(nrm.x)
			for r in hrows:
				var y := (r + 0.5) * rs
				var keep := func(t: float, _p: Vector3) -> Vector2:
					var es := minf(t, 1.0 - t) * PILLAR_W
					var k := smoothstep(0.0, edge, es) * smoothstep(0.0, edge * 0.8, PILLAR_H - y) * (0.3 + 0.7 * smoothstep(0.0, edge * 1.2, y))
					return Vector2(0.2 + 0.8 * k, k)
				_row(a + Vector3(0, y, 0), b + Vector3(0, y, 0), r, rs, 0.0, keep, pi * 1000.0 + f * 100.0 + r)
	_shade = 1.0
	var world_n := _cnt
	_add_points("World", _buf, world_n, {"pt_step": _k("step"), "min_dot_px": _k("min_dot_px")})
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
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = n
	mm.buffer = buf
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 15, 40))
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/look_v11/scan_point.gdshader")
	m.set_shader_parameter("vp_h", float(get_viewport().get_visible_rect().size.y))
	for key in ["min_px", "min_row_px", "fade_near", "fade_far", "fade_min"]:
		m.set_shader_parameter(key, K[key])
	for key in params:
		m.set_shader_parameter(key, params[key])
	mi.material_override = m
	add_child(mi)


## Непрозрачность граней (решение 19.10): тело колонны цвета пустоты пишет глубину — сквозь колонну не видно, что за ней.
func _add_occluders() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = VOID
	for pc in PILLARS:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(PILLAR_W - 0.01, PILLAR_H - 0.01, PILLAR_W - 0.01)
		b.mesh = bm
		b.material_override = m
		b.position = Vector3(pc.x, PILLAR_H * 0.5, pc.y)
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
	var rs := 0.011
	var dark := RED_DARK.lerp(RED, 0.4).srgb_to_linear()  # тело светится само: тусклый малиновый, кромка — ядро
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
			var n := int(TAU * rad / 0.008)
			for i in n:
				var a := (float(i) + _rand() * 0.6) / float(maxi(n, 1)) * TAU
				var lp := Vector3(cos(a) * rad, y, sin(a) * rad)
				var nrm := xf.basis * (lp - Vector3(0, cy, 0)).normalized()
				var b := (0.7 + 0.8 * _rand()) * _k("fig")
				_push(xf * lp, Color(dark.r * b, dark.g * b, dark.b * b), 0, rs, 3.0, 0.0075, nrm)
			y += rs
	_add_points("Figure", _buf, _cnt, {"rim_gain": _k("fig"), "rim_col": RED, "fade_min": 0.6})


func _k(n: String) -> float:
	return float(K[n])
