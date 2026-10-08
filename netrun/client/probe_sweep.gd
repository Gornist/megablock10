class_name ProbeSweep
extends Node
## Серия вариантов LoadProbe за один запуск (`[render] probe = "sweep"`): база без нагрузки, затем по порядку LoadProbe.SWEEP. На вариант — SETTLE_SEC прогрева
## и WINDOW_SEC замера (среднее время кадра и GPU-время вида); итог каждого — строка `[probe]`, в конце `[probe] ИТОГ` со всеми разностями к базе.
## Нужна, чтобы не снимать и надевать очки на каждый вариант. Нагрузка приклеена к камере, поза не важна (голову не вертеть).

signal finished(results: Array)

const SETTLE_SEC := 3.0
const WINDOW_SEC := 10.0

var results: Array = []

var _camera: Node3D
var _specs: Array = []   # "" — база
var _idx := -1
var _probe: Node
var _t := 0.0
var _measuring := false
var _frames := 0
var _sum_ms := 0.0
var _max_ms := 0.0
var _gpu_sum := 0.0
var _gpu_n := 0
var _vp_rid := RID()
var _done := false


func setup(camera: Node3D) -> void:
	_camera = camera
	_specs = [""]
	_specs.append_array(LoadProbe.SWEEP)


func _ready() -> void:
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	_next_variant()


func _process(delta: float) -> void:
	step(delta, _gpu_ms())


func is_done() -> bool:
	return _done


## Один кадр серии (delta в с, gpu_ms −1 — нет данных); вынесено, чтобы тест гнал время вручную.
func step(delta: float, gpu_ms: float) -> void:
	if _done:
		return
	_t += delta
	if not _measuring:
		if _t >= SETTLE_SEC:
			_measuring = true
			_t = 0.0
		return
	_frames += 1
	var ms := delta * 1000.0
	_sum_ms += ms
	_max_ms = maxf(_max_ms, ms)
	if gpu_ms >= 0.0:
		_gpu_sum += gpu_ms
		_gpu_n += 1
	if _t >= WINDOW_SEC:
		var r := BenchRun.summarize_run(_frames, _sum_ms, _max_ms, _t, _gpu_sum, _gpu_n)
		r["spec"] = _specs[_idx] if _specs[_idx] != "" else "base"
		results.append(r)
		print(format_variant(r))
		_next_variant()


func _next_variant() -> void:
	if is_instance_valid(_probe):
		_probe.queue_free()
		_probe = null
	_idx += 1
	_t = 0.0
	_measuring = false
	_frames = 0
	_sum_ms = 0.0
	_max_ms = 0.0
	_gpu_sum = 0.0
	_gpu_n = 0
	if _idx >= _specs.size():
		_done = true
		print(format_summary(results))
		finished.emit(results)
		return
	if _specs[_idx] != "" and _camera != null:
		var p := LoadProbe.new()
		p.setup(LoadProbe.parse(_specs[_idx]))
		_camera.add_child(p)
		_probe = p


func _gpu_ms() -> float:
	if not _vp_rid.is_valid():
		return -1.0
	var t := RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	return t if t > 0.0 else -1.0


static func format_variant(r: Dictionary) -> String:
	return "[probe] %s fps=%s avg_ms=%s max_ms=%s gpu_ms=%s" % [r["spec"], r["fps"], r["avg_ms"], r["max_ms"], r["gpu_avg_ms"]]


## Сводка: по строке на вариант с разностью GPU к базе (первый результат).
static func format_summary(res: Array) -> String:
	var lines := PackedStringArray(["[probe] ИТОГ (gpu_ms, разность к базе)"])
	if res.is_empty():
		return lines[0]
	var base := float(res[0]["gpu_avg_ms"])
	for r: Dictionary in res:
		var g := float(r["gpu_avg_ms"])
		var d := "" if r == res[0] or g < 0.0 or base < 0.0 else " (%+.2f)" % (g - base)
		lines.append("[probe]   %s: gpu=%s%s fps=%s" % [r["spec"], r["gpu_avg_ms"], d, r["fps"]])
	return "\n".join(lines)
