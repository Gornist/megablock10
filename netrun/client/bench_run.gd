class_name BenchRun
extends Node
## Воспроизводимый замер кадра на очках (`[render] bench = "<пресет EyePresets>"`, шаги Ш0 плана «волюметрик» и G0): шум между сеансами ±1 мс не даёт мерить цену
## отдельных слоёв («≤ +1,0 мс»), поэтому замер идёт одной позой, окнами подряд, а итог — медиана окон и перцентили по сырым кадрам. Порядок: settle_s секунд на сборку
## узла и прогрев шейдеров → камера ставится в позу пресета (bench_lock: КАЖДЫЙ кадр, поза XRCamera3D целиком, трекинг компенсируется — очки лежат на столе) →
## runs окон по run_s секунд. Каждый кадр окна — строка CSV (user://bench/<пресет>-<время>.csv, запись в конце окна), в журнал — итог окна и общий итог.
## A/B внутри одной сессии (bench_ab = "имя=a|b"): окна идут A,B,A,B…, перед каждым применяется значение и выдерживается ab_settle_s без учёта; итог — разница B−A.
## GPU-время — RenderingServer.viewport_get_measured_render_time_gpu.

signal finished(result: Dictionary)
## Конец прогрева: подписчик (сам узел в _ready) ставит позу и печатает диагностику проекции. Вынесено из step, чтобы тест гнал время без рендерера.
signal settled
## Смена варианта A/B перед окном: подписчик применяет значение (msaa или ручку). В тестах не подключён.
signal variant_changed(knob: String, value: String)

const SETTLE_SEC := 10.0
const RUNS := 3
const RUN_SEC := 20.0
const AB_SETTLE_SEC := 2.0
## Бюджет кадра 90 Гц, мс: доля кадров дольше него — главный показатель замера.
const OVER_MS := 11.11
const CSV_HEADER := "run,variant,frame,t_ms,frame_ms,gpu_ms"
## Ручки AssetMaterials, что меняются живьём: имя → uniform шейдера cloud_dark.gdshader (прямой 1:1; у всех cloud_dark-материалов, уже созданных apply()).
const LIVE_UNIFORMS := {
	"dust_cell": "dust_cell", "dust_fps": "dust_fps", "dust_fill": "dust_fill", "dust_fill_lo": "dust_fill_lo",
	"dust_fill_hi": "dust_fill_hi", "dust_sharp": "dust_sharp", "cloud_edge_mix": "edge_mix",
}
## Ручки света облака: несколько uniform сразу, их выставляет AssetMaterials._push_cloud_light_knobs по обновлённой ручке (tune).
const LIVE_LIGHT := ["cloud_light", "lit_ambient", "lit_dim", "lit_edge", "lit_tint"]
const MSAA_VALUES := [0, 2, 4, 8]

var preset := ""
var result: Dictionary = {}
## Итог A/B (ab_summary) или пусто.
var ab_result: Dictionary = {}
## Поза камеры целиком каждый кадр (true) или один раз по позиции и рысканию (false).
var lock := true
var settle_s := SETTLE_SEC
var runs := RUNS
var run_s := RUN_SEC
var ab_settle_s := AB_SETTLE_SEC
## Путь CSV (user://…); пусто — файл не пишется (тесты).
var csv_path := ""

var _rig: Node3D
var _state := "settle"   # settle → (ab_settle →) run → … → done
var _t := 0.0
var _run := 0
var _frames := 0
var _sum_ms := 0.0
var _max_ms := 0.0
var _gpu_sum := 0.0
var _gpu_n := 0
var _win_frame := PackedFloat64Array()
var _win_gpu := PackedFloat64Array()
var _all_frame := PackedFloat64Array()
var _all_gpu := PackedFloat64Array()
var _csv_lines := PackedStringArray()
var _runs: Array = []
var _by_variant: Array = [[], []]
var _vp_rid := RID()
var _ab: Dictionary = {}          # parse_ab(...) принятого A/B; пусто — выкл.
var _variant := -1                # вариант текущего окна: 0 — A, 1 — B, −1 — без A/B
var _cam_target := Transform3D()
var _locked := false


## rig — риг игрока (XRRig), preset_name — имя пресета EyePresets, cfg — настройки замера [render] (null — умолчания). Отказ A/B — строкой `[bench] ab: …`, замер идёт без него.
func setup(rig: Node3D, preset_name: String, cfg: RefCounted = null) -> void:
	_rig = rig
	preset = preset_name
	if cfg == null:
		return
	lock = cfg.bench_lock
	settle_s = cfg.bench_settle_s
	runs = cfg.bench_runs
	run_s = cfg.bench_run_s
	ab_settle_s = cfg.bench_ab_settle_s
	var refusal := configure_ab(cfg.bench_ab)
	if refusal != "":
		print("[bench] ab: " + refusal)


## Принять A/B-спецификацию. Пустая строка — ничего не делает. Возвращает "" (принято, runs округлён вверх до чётного) или причину отказа (A/B выключен, замер без него).
func configure_ab(spec: String) -> String:
	_ab = {}
	if spec.strip_edges() == "":
		return ""
	var ab := parse_ab(spec)
	if not ab["ok"]:
		return ab["error"]
	var name_: String = ab["name"]
	var kind := knob_kind(name_)
	if kind == "unknown":
		return "неизвестная ручка «%s»" % name_
	if kind == "static":
		return "ручка %s не меняется живьём" % name_
	for v: String in [ab["a"], ab["b"]]:
		if not value_valid(name_, v):
			return "значение «%s» не годится для %s" % [v, name_]
	_ab = ab
	runs = ab_runs(runs)
	return ""


func _ready() -> void:
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	settled.connect(_on_settled)
	variant_changed.connect(_on_variant_changed)
	csv_path = "user://bench/%s-%s.csv" % [preset, timestamp(Time.get_datetime_dict_from_system())]
	DirAccess.make_dir_recursive_absolute("user://bench")


func _process(delta: float) -> void:
	if _locked:
		_lock_pose()
	step(delta, _gpu_ms())


## Один кадр замера: delta (с), gpu_ms (−1 — рендерер не отдал). Вынесено из _process, чтобы тест гнал время вручную.
func step(delta: float, gpu_ms: float) -> void:
	if _state == "done":
		return
	_t += delta
	if _state == "settle":
		if _t >= settle_s:
			settled.emit()
			_begin_window()
		return
	if _state == "ab_settle":
		if _t >= ab_settle_s:
			_state = "run"
			_t = 0.0
			_reset_run()
		return
	_frames += 1
	var ms := delta * 1000.0
	_sum_ms += ms
	_max_ms = maxf(_max_ms, ms)
	if gpu_ms >= 0.0:
		_gpu_sum += gpu_ms
		_gpu_n += 1
	_win_frame.append(ms)
	_win_gpu.append(gpu_ms)
	_csv_lines.append(csv_row(_run + 1, variant_label(_variant), _frames - 1, _t * 1000.0, ms, gpu_ms))
	if _t >= run_s:
		_end_window()


func is_done() -> bool:
	return _state == "done"


## Номер варианта окна: 0 — A, 1 — B, −1 — без A/B.
func current_variant() -> int:
	return _variant


func _begin_window() -> void:
	_t = 0.0
	_reset_run()
	if _ab.is_empty():
		_variant = -1
		_state = "run"
		return
	_variant = ab_schedule(runs)[_run]
	variant_changed.emit(_ab["name"], _ab["a"] if _variant == 0 else _ab["b"])
	_state = "ab_settle" if ab_settle_s > 0.0 else "run"


func _end_window() -> void:
	var r := summarize_run(_frames, _sum_ms, _max_ms, _t, _gpu_sum, _gpu_n)
	r.merge(frame_stats(_win_frame, _win_gpu))
	if _variant >= 0:
		r["variant"] = variant_label(_variant)
		_by_variant[_variant].append(r)
	_runs.append(r)
	_all_frame.append_array(_win_frame)
	_all_gpu.append_array(_win_gpu)
	print(format_run(_runs.size(), r))
	_flush_csv()
	_run += 1
	if _run < runs:
		_begin_window()
		return
	_state = "done"
	result = median_result(_runs)
	result.merge(frame_stats(_all_frame, _all_gpu))
	result["preset"] = preset
	if not _ab.is_empty():
		ab_result = ab_summary(_by_variant[0], _by_variant[1])
		for v in 2:
			print(format_ab_variant(_ab["name"], v, _ab["a"] if v == 0 else _ab["b"], ab_result["a" if v == 0 else "b"]))
		print(format_ab(_ab["name"], _ab["a"], _ab["b"], ab_result))
	if csv_path != "":
		print("[bench] csv=" + ProjectSettings.globalize_path(csv_path))
	print(format_result(result))
	finished.emit(result)


func _reset_run() -> void:
	_frames = 0
	_sum_ms = 0.0
	_max_ms = 0.0
	_gpu_sum = 0.0
	_gpu_n = 0
	_win_frame = PackedFloat64Array()
	_win_gpu = PackedFloat64Array()


func _flush_csv() -> void:
	if csv_path == "":
		return
	var f := FileAccess.open(csv_path, FileAccess.WRITE)
	if f == null:
		print("[bench] csv: не открыть %s (%s)" % [csv_path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(CSV_HEADER + "\n" + "\n".join(_csv_lines) + "\n")
	f.close()


func _gpu_ms() -> float:
	if not _vp_rid.is_valid():
		return -1.0
	var t := RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	return t if t > 0.0 else -1.0


func _camera() -> Camera3D:
	if _rig == null:
		return null
	return _rig.get("camera") as Camera3D


## Конец прогрева: поза камеры (с компенсацией трекинга — bench_lock — либо один раз по позиции и рысканию), диагностика проекции.
func _on_settled() -> void:
	var p := EyePresets.get_preset(preset)
	if not p.is_empty() and _rig != null:
		if lock and _camera() != null:
			_cam_target = preset_camera_transform(p)
			_locked = true
			_lock_pose()
		else:
			_place_rig(p)
	print(proj_line(_proj_p11(), get_viewport().get_visible_rect().size, msaa_number(get_viewport().msaa_3d)))


## Поза рига так, чтобы глобальная поза камеры = поза пресета при любом трекинге.
func _lock_pose() -> void:
	var cam := _camera()
	if _rig == null or cam == null:
		return
	_rig.global_transform = lock_transform(_cam_target, cam.transform)


## Прежний режим (bench_lock = false): риг на пол под точкой глаз и лицом к точке взгляда.
func _place_rig(p: Dictionary) -> void:
	var eye: Vector3 = p["pos"]
	_rig.global_position = Vector3(eye.x, 0.0, eye.z)
	if _rig.has_method("face_toward"):
		_rig.call("face_toward", p["look"])


## [1][1] проекции левого и правого глаза: у XR-интерфейса — get_projection_for_view, иначе (плоский клиент) — проекция камеры для обоих.
func _proj_p11() -> Array:
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var cam := _camera()
	var near := cam.near if cam != null else 0.05
	var far := cam.far if cam != null else 4000.0
	var iface := XRServer.primary_interface
	if iface != null:
		return [iface.get_projection_for_view(0, aspect, near, far).y.y, iface.get_projection_for_view(1, aspect, near, far).y.y]
	if cam != null:
		var p11 := cam.get_camera_projection().y.y
		return [p11, p11]
	return [NAN, NAN]


func _on_variant_changed(name_: String, value: String) -> void:
	if name_ == "msaa":
		get_viewport().msaa_3d = msaa_viewport_mode(int(value))
		return
	var f := float(value)
	AssetMaterials.tune({name_: f})   # последующие материалы и сами ручки света читают _k()
	for m: ShaderMaterial in AssetMaterials._cloud_materials(get_tree()):
		if m.shader != AssetMaterials.CLOUD_SHADER:
			continue
		if LIVE_UNIFORMS.has(name_):
			m.set_shader_parameter(LIVE_UNIFORMS[name_], f)
		else:
			AssetMaterials._push_cloud_light_knobs(m)


# --- чистые функции (без сцены и рендерера) ---

## Поза камеры пресета в мире: позиция глаз, −Z на точку взгляда, up пресета.
static func preset_camera_transform(p: Dictionary) -> Transform3D:
	var pos: Vector3 = p["pos"]
	var up: Vector3 = p.get("up", Vector3.UP)
	return Transform3D(Basis.looking_at(((p["look"] as Vector3) - pos).normalized(), up), pos)


## Поза рига, при которой глобальная поза дочерней камеры (локальная cam_local — от трекинга) равна target.
static func lock_transform(target: Transform3D, cam_local: Transform3D) -> Transform3D:
	return target * cam_local.affine_inverse()


## Перцентиль q (0…1) по сырым значениям: сортировка, индекс ceil(q·n) − 1. Пусто — 0.
static func percentile(values: PackedFloat64Array, q: float) -> float:
	var s := values.duplicate()
	if s.is_empty():
		return 0.0
	s.sort()
	var idx := clampi(int(ceil(q * s.size())) - 1, 0, s.size() - 1)
	return s[idx]


## Статистика по кадрам окна (или всего замера): p50/p95/max и доля кадров дольше OVER_MS для времени кадра и GPU. GPU: кадры без данных (−1) не считаются; нет данных — −1.
static func frame_stats(f: PackedFloat64Array, gpu_ms: PackedFloat64Array) -> Dictionary:
	var g := PackedFloat64Array()
	for v in gpu_ms:
		if v >= 0.0:
			g.append(v)
	return {
		"frame_p50": snappedf(percentile(f, 0.5), 0.01),
		"frame_p95": snappedf(percentile(f, 0.95), 0.01),
		"frame_peak": snappedf(_peak(f), 0.01),
		"frame_over": over_share(f),
		"gpu_p50": snappedf(percentile(g, 0.5), 0.01) if not g.is_empty() else -1.0,
		"gpu_p95": snappedf(percentile(g, 0.95), 0.01) if not g.is_empty() else -1.0,
		"gpu_peak": snappedf(_peak(g), 0.01) if not g.is_empty() else -1.0,
		"gpu_over": over_share(g) if not g.is_empty() else -1.0,
	}


static func _peak(values: PackedFloat64Array) -> float:
	var m := 0.0
	for v in values:
		m = maxf(m, v)
	return m


## Доля значений строго больше OVER_MS (0…1, три знака).
static func over_share(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var n := 0
	for v in values:
		if v > OVER_MS:
			n += 1
	return snappedf(float(n) / values.size(), 0.001)


## Строка CSV кадра: run (с 1), variant (A/B/-), frame (с 0), t_ms от начала окна, frame_ms, gpu_ms (−1 — нет данных).
static func csv_row(run: int, variant: String, frame: int, t_ms: float, frame_ms: float, gpu_ms: float) -> String:
	return "%d,%s,%d,%.2f,%.3f,%.3f" % [run, variant, frame, t_ms, frame_ms, gpu_ms]


## Время для имени CSV: ГГГГММДД-ЧЧММСС из словаря Time.get_datetime_dict_from_system().
static func timestamp(dt: Dictionary) -> String:
	return "%04d%02d%02d-%02d%02d%02d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"]]


static func variant_label(v: int) -> String:
	return "-" if v < 0 else ("A" if v == 0 else "B")


## Число окон при A/B: вверх до чётного (не меньше 2), чтобы A и B были в равном числе.
static func ab_runs(n: int) -> int:
	return maxi(2, n + (n % 2))


## Расписание окон A,B,A,B… (0 — A, 1 — B) на runs окон (округлено вверх до чётного).
static func ab_schedule(n: int) -> Array:
	var out: Array = []
	for i in ab_runs(n):
		out.append(i % 2)
	return out


## Разбор «имя=a|b»: {ok, name, a, b, error}. Имя и оба значения непусты, ровно два варианта.
static func parse_ab(spec: String) -> Dictionary:
	var s := spec.strip_edges()
	var eq := s.find("=")
	if eq <= 0:
		return {"ok": false, "name": "", "a": "", "b": "", "error": "ожидалось «имя=a|b», получено «%s»" % s}
	var name_ := s.substr(0, eq).strip_edges()
	var parts := s.substr(eq + 1).split("|")
	if parts.size() != 2 or parts[0].strip_edges() == "" or parts[1].strip_edges() == "":
		return {"ok": false, "name": name_, "a": "", "b": "", "error": "нужны два значения через «|» после «%s=», получено «%s»" % [name_, s.substr(eq + 1)]}
	return {"ok": true, "name": name_, "a": parts[0].strip_edges(), "b": parts[1].strip_edges(), "error": ""}


## Что за имя в bench_ab: "msaa", "live" (ручка меняется на созданных материалах), "static" (ручка читается при создании материалов), "unknown".
static func knob_kind(name_: String) -> String:
	if name_ == "msaa":
		return "msaa"
	if LIVE_UNIFORMS.has(name_) or name_ in LIVE_LIGHT:
		return "live"
	if AssetMaterials.KNOBS.has(name_):
		return "static"
	return "unknown"


## Значение годится для имени: msaa — 0/2/4/8, живая ручка — число.
static func value_valid(name_: String, value: String) -> bool:
	if name_ == "msaa":
		return value.is_valid_int() and int(value) in MSAA_VALUES
	return value.is_valid_float()


## Viewport.MSAA по числу 0/2/4/8.
static func msaa_viewport_mode(n: int) -> Viewport.MSAA:
	match n:
		2:
			return Viewport.MSAA_2X
		4:
			return Viewport.MSAA_4X
		8:
			return Viewport.MSAA_8X
	return Viewport.MSAA_DISABLED


## Число 0/2/4/8 по режиму Viewport.
static func msaa_number(mode: int) -> int:
	match mode:
		Viewport.MSAA_2X:
			return 2
		Viewport.MSAA_4X:
			return 4
		Viewport.MSAA_8X:
			return 8
	return 0


## Строка диагностики проекции: знак [1][1] (PROJECTION_MATRIX[1][1] в шейдерах), размер вида, MSAA.
static func proj_line(p11: Array, size: Vector2, msaa: int) -> String:
	return "[bench] proj p11_l=%.4f p11_r=%.4f viewport=%dx%d msaa=%d" % [p11[0], p11[1], int(size.x), int(size.y), msaa]


## Итог одного прогона: fps, среднее и максимум времени кадра, среднее GPU-время (−1 — нет данных).
static func summarize_run(frames: int, sum_ms: float, max_ms: float, elapsed: float, gpu_sum: float, gpu_n: int) -> Dictionary:
	var n := maxi(frames, 1)
	return {
		"fps": snappedf(float(frames) / maxf(elapsed, 0.001), 0.1),
		"avg_ms": snappedf(sum_ms / n, 0.01),
		"max_ms": snappedf(max_ms, 0.01),
		"gpu_avg_ms": snappedf(gpu_sum / gpu_n, 0.01) if gpu_n > 0 else -1.0,
	}


## Медиана массива чисел (для чётного числа — среднее двух средних).
static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	var n := s.size()
	return float(s[n / 2]) if n % 2 == 1 else (float(s[n / 2 - 1]) + float(s[n / 2])) * 0.5


## Медиана по прогонам для каждого поля.
static func median_result(run_list: Array) -> Dictionary:
	var out := {"runs": run_list.size()}
	for k in ["fps", "avg_ms", "max_ms", "gpu_avg_ms"]:
		var vals: Array = []
		for r: Dictionary in run_list:
			vals.append(float(r[k]))
		out[k] = snappedf(median(vals), 0.01)
		if k == "gpu_avg_ms" or k == "avg_ms":   # разброс окон: шум короткого замера виден в итоге
			out[k + "_min"] = snappedf(vals.min(), 0.01)
			out[k + "_max"] = snappedf(vals.max(), 0.01)
	return out


## Поля окна, по которым считается итог варианта A/B.
const AB_KEYS := ["avg_ms", "gpu_avg_ms", "frame_p50", "frame_p95", "gpu_p50", "gpu_p95"]


## Итог A/B: по каждому варианту — медиана окон по AB_KEYS; d_* = B − A (null, если у одного из вариантов нет данных GPU).
static func ab_summary(windows_a: Array, windows_b: Array) -> Dictionary:
	var out := {"a": _variant_medians(windows_a), "b": _variant_medians(windows_b)}
	for k in ["gpu_p50", "gpu_p95", "frame_p50", "frame_p95", "gpu_avg_ms", "avg_ms"]:
		var a: float = out["a"][k]
		var b: float = out["b"][k]
		out["d_" + k] = snappedf(b - a, 0.01) if (a >= 0.0 and b >= 0.0) else null
	return out


static func _variant_medians(windows: Array) -> Dictionary:
	var out := {"windows": windows.size()}
	for k in AB_KEYS:
		var vals: Array = []
		for w: Dictionary in windows:
			vals.append(float(w.get(k, -1.0)))
		out[k] = snappedf(median(vals), 0.01) if not vals.is_empty() else -1.0
	return out


static func _d(v: Variant) -> String:
	return "n/a" if v == null else str(v)


static func format_run(i: int, r: Dictionary) -> String:
	var s := "[bench] run=%d fps=%s avg_ms=%s max_ms=%s gpu_avg_ms=%s" % [i, r["fps"], r["avg_ms"], r["max_ms"], r["gpu_avg_ms"]]
	if r.has("frame_p50"):   # новые поля — в конец, прежние на месте
		s += " " + stats_fields(r)
	if r.has("variant"):
		s += " variant=" + str(r["variant"])
	return s


static func stats_fields(r: Dictionary) -> String:
	return "frame_p50=%s frame_p95=%s frame_peak=%s frame_over=%s gpu_p50=%s gpu_p95=%s gpu_peak=%s gpu_over=%s" % [r["frame_p50"], r["frame_p95"], r["frame_peak"], r["frame_over"],
		r["gpu_p50"], r["gpu_p95"], r["gpu_peak"], r["gpu_over"]]


static func format_result(r: Dictionary) -> String:
	var s := "[bench] ИТОГ preset=%s runs=%s median_fps=%s median_avg_ms=%s median_gpu_ms=%s gpu_min=%s gpu_max=%s avg_min=%s avg_max=%s" % [r.get("preset", ""), r["runs"], r["fps"], r["avg_ms"], r["gpu_avg_ms"],
		r.get("gpu_avg_ms_min", r["gpu_avg_ms"]), r.get("gpu_avg_ms_max", r["gpu_avg_ms"]), r.get("avg_ms_min", r["avg_ms"]), r.get("avg_ms_max", r["avg_ms"])]
	if r.has("frame_p50"):
		s += " " + stats_fields(r)
	return s


static func format_ab(name_: String, a: String, b: String, ab: Dictionary) -> String:
	return "[bench] AB name=%s a=%s b=%s d_gpu_p50=%s d_gpu_p95=%s d_frame_p50=%s" % [name_, a, b, _d(ab["d_gpu_p50"]), _d(ab["d_gpu_p95"]), _d(ab["d_frame_p50"])]


## По варианту: медианы его окон.
static func format_ab_variant(name_: String, v: int, value: String, m: Dictionary) -> String:
	return "[bench] AB-var name=%s variant=%s value=%s windows=%s gpu_avg=%s gpu_p50=%s gpu_p95=%s frame_avg=%s frame_p50=%s frame_p95=%s" % [name_, variant_label(v), value, m["windows"], m["gpu_avg_ms"],
		m["gpu_p50"], m["gpu_p95"], m["avg_ms"], m["frame_p50"], m["frame_p95"]]
