class_name BenchRun
extends Node
## Воспроизводимый замер кадра на очках (`[render] bench = "<пресет EyePresets>"`, шаг Ш0 плана «волюметрик»): шум между сеансами ±1 мс не даёт мерить цену
## отдельных слоёв («≤ +1,0 мс»), поэтому замер идёт одной позой и несколько прогонов подряд, а итог — медиана. Порядок: SETTLE_SEC секунд на сборку узла и
## прогрев шейдеров → риг ставится в позу пресета (позиция и поворот вокруг головы; голову в очках игрок не должен вертеть) → RUNS прогонов по RUN_SEC секунд,
## в каждом среднее время кадра и GPU-время вида → строка `[bench]` с медианой по прогонам. GPU-время — RenderingServer.viewport_get_measured_render_time_gpu.

signal finished(result: Dictionary)

const SETTLE_SEC := 15.0
const RUNS := 3
const RUN_SEC := 60.0

var preset := ""
var result: Dictionary = {}

var _rig: Node3D
var _state := "settle"   # settle → run → done
var _t := 0.0
var _run := 0
var _frames := 0
var _sum_ms := 0.0
var _max_ms := 0.0
var _gpu_sum := 0.0
var _gpu_n := 0
var _runs: Array = []
var _vp_rid := RID()


## rig — риг игрока (XRRig), preset — имя пресета EyePresets (entry, north, south, vault_w, …).
func setup(rig: Node3D, preset_name: String) -> void:
	_rig = rig
	preset = preset_name


func _ready() -> void:
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)


func _process(delta: float) -> void:
	step(delta, _gpu_ms())


## Один кадр замера: delta (с), gpu_ms (−1 — рендерер не отдал). Вынесено из _process, чтобы тест гнал время вручную.
func step(delta: float, gpu_ms: float) -> void:
	if _state == "done":
		return
	_t += delta
	if _state == "settle":
		if _t >= SETTLE_SEC:
			_place_rig()
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
	if _t >= RUN_SEC:
		_runs.append(summarize_run(_frames, _sum_ms, _max_ms, _t, _gpu_sum, _gpu_n))
		print(format_run(_runs.size(), _runs[-1]))
		_run += 1
		_reset_run()
		_t = 0.0
		if _run >= RUNS:
			_state = "done"
			result = median_result(_runs)
			result["preset"] = preset
			print(format_result(result))
			finished.emit(result)


func is_done() -> bool:
	return _state == "done"


func _reset_run() -> void:
	_frames = 0
	_sum_ms = 0.0
	_max_ms = 0.0
	_gpu_sum = 0.0
	_gpu_n = 0


func _gpu_ms() -> float:
	if not _vp_rid.is_valid():
		return -1.0
	var t := RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	return t if t > 0.0 else -1.0


## Ставит риг в позу пресета: на пол под точкой глаз и лицом к точке взгляда. Нет пресета или рига — замер идёт из текущей позы.
func _place_rig() -> void:
	var p := EyePresets.get_preset(preset)
	if p.is_empty() or _rig == null:
		return
	var eye: Vector3 = p["pos"]
	_rig.global_position = Vector3(eye.x, 0.0, eye.z)
	if _rig.has_method("face_toward"):
		_rig.call("face_toward", p["look"])


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
static func median_result(runs: Array) -> Dictionary:
	var out := {"runs": runs.size()}
	for k in ["fps", "avg_ms", "max_ms", "gpu_avg_ms"]:
		var vals: Array = []
		for r: Dictionary in runs:
			vals.append(float(r[k]))
		out[k] = snappedf(median(vals), 0.01)
	return out


static func format_run(i: int, r: Dictionary) -> String:
	return "[bench] run=%d fps=%s avg_ms=%s max_ms=%s gpu_avg_ms=%s" % [i, r["fps"], r["avg_ms"], r["max_ms"], r["gpu_avg_ms"]]


static func format_result(r: Dictionary) -> String:
	return "[bench] ИТОГ preset=%s runs=%s median_fps=%s median_avg_ms=%s median_gpu_ms=%s" % [r.get("preset", ""), r["runs"], r["fps"], r["avg_ms"], r["gpu_avg_ms"]]
