class_name FramePerf
extends Node
## Счётчик времени кадра для стенда на очках (`[render] perf = "on"`): раз в INTERVAL_SEC секунд считает кадры, среднее и максимальное время кадра,
## GPU-время вида (RenderingServer.viewport_get_measured_render_time_gpu, если рендерер его отдаёт) и печатает строку `[perf] …` — она попадает в logcat
## и, через сигнал reported, в журнал клиента. Нужен, чтобы подбирать scale / фовеацию по числам, а не по ощущениям (72 Гц = кадр ≤ 13,9 мс).

signal reported(stats: Dictionary)

const INTERVAL_SEC := 5.0
## Бюджет кадра очков Pico 4 при 72 Гц, мс.
const BUDGET_MS := 1000.0 / 72.0

var last: Dictionary = {}

var _frames := 0
var _sum_ms := 0.0
var _max_ms := 0.0
var _elapsed := 0.0
var _vp_rid := RID()


func _ready() -> void:
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)


func _process(delta: float) -> void:
	feed(delta, _gpu_ms())


## Один кадр: delta (с) и GPU-время (мс, −1 — рендерер не отдал). Когда накопилось INTERVAL_SEC — итог и сброс.
func feed(delta: float, gpu_ms: float) -> void:
	_frames += 1
	var ms := delta * 1000.0
	_sum_ms += ms
	_max_ms = maxf(_max_ms, ms)
	_elapsed += delta
	if gpu_ms >= 0.0:
		_gpu_sum += gpu_ms
		_gpu_n += 1
		_gpu_max = maxf(_gpu_max, gpu_ms)
	if _elapsed >= INTERVAL_SEC:
		last = summarize(_frames, _sum_ms, _max_ms, _elapsed, _gpu_sum, _gpu_n, _gpu_max)
		print(format(last))
		reported.emit(last)
		_frames = 0
		_sum_ms = 0.0
		_max_ms = 0.0
		_elapsed = 0.0
		_gpu_sum = 0.0
		_gpu_n = 0
		_gpu_max = 0.0


var _gpu_sum := 0.0
var _gpu_n := 0
var _gpu_max := 0.0


func _gpu_ms() -> float:
	if not _vp_rid.is_valid():
		return -1.0
	var t := RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	return t if t > 0.0 else -1.0


## Чистая сводка за окно: fps, среднее и максимум времени кадра, доля кадров не уложилась (по среднему бюджету), GPU среднее/максимум (−1 — нет данных).
static func summarize(frames: int, sum_ms: float, max_ms: float, elapsed: float, gpu_sum: float, gpu_n: int, gpu_max: float) -> Dictionary:
	var n := maxi(frames, 1)
	return {
		"fps": snappedf(float(frames) / maxf(elapsed, 0.001), 0.1),
		"avg_ms": snappedf(sum_ms / n, 0.01),
		"max_ms": snappedf(max_ms, 0.01),
		"over_budget": sum_ms / n > BUDGET_MS,
		"gpu_avg_ms": snappedf(gpu_sum / gpu_n, 0.01) if gpu_n > 0 else -1.0,
		"gpu_max_ms": snappedf(gpu_max, 0.01) if gpu_n > 0 else -1.0,
	}


static func format(s: Dictionary) -> String:
	return "[perf] fps=%s avg_ms=%s max_ms=%s gpu_avg_ms=%s gpu_max_ms=%s over_budget=%s" % [s["fps"], s["avg_ms"], s["max_ms"], s["gpu_avg_ms"], s["gpu_max_ms"], s["over_budget"]]
