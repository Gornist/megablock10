class_name VolumeBudget
extends Node
## Регулятор плотности облаков по GPU-времени кадра (план «волюметрик», шаг «volume_budget_ms»). `[render] volume_budget_ms = N` — потолок GPU-времени кадра, мс
## (при 90 Гц бюджет кадра 11,1 мс, потолок ≈ 10,5): раз в WINDOW_SEC берётся среднее GPU-время вида; выше потолка — плотность всех облаков (группа
## `volume_clouds`, VolumeCloud.set_density) падает на ступень, заметно ниже потолка (на HYSTERESIS_MS) — растёт обратно. 0 — регулятор выключен (по умолчанию).
## Плотность — множитель к префиксу точек (ЛОД по расстоянию остаётся): падение выкидывает хвост перемешанного массива, вид редеет равномерно.

signal changed(density: float)

const WINDOW_SEC := 1.0
const STEP_DOWN := 0.8
const STEP_UP := 1.1
const MIN_DENSITY := 0.25
const MAX_DENSITY := 1.0
const HYSTERESIS_MS := 0.8
const GROUP := "volume_clouds"

## Потолок GPU-времени кадра, мс; 0 — регулятор не работает.
var limit_ms := 0.0
var density := MAX_DENSITY

var _acc := 0.0
var _gpu_sum := 0.0
var _gpu_n := 0
var _vp_rid := RID()


func _ready() -> void:
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)


func _process(delta: float) -> void:
	feed(delta, _gpu_ms())


## Один кадр: delta (с), gpu_ms (−1 — рендерер не отдал). Вынесено из _process, чтобы тесты гнали время вручную.
func feed(delta: float, gpu_ms: float) -> void:
	if limit_ms <= 0.0:
		return
	_acc += delta
	if gpu_ms >= 0.0:
		_gpu_sum += gpu_ms
		_gpu_n += 1
	if _acc < WINDOW_SEC:
		return
	var mean := _gpu_sum / _gpu_n if _gpu_n > 0 else -1.0
	_acc = 0.0
	_gpu_sum = 0.0
	_gpu_n = 0
	var next := next_density(density, mean, limit_ms)
	if not is_equal_approx(next, density):
		density = next
		_apply()
		changed.emit(density)


## Новая плотность по среднему GPU-времени окна: выше потолка — ступень вниз, ниже потолка на гистерезис — ступень вверх; нет данных (< 0) — без изменений.
static func next_density(current: float, mean_gpu_ms: float, limit: float) -> float:
	if limit <= 0.0 or mean_gpu_ms < 0.0:
		return current
	if mean_gpu_ms > limit:
		return maxf(MIN_DENSITY, current * STEP_DOWN)
	if mean_gpu_ms < limit - HYSTERESIS_MS:
		return minf(MAX_DENSITY, current * STEP_UP)
	return current


func _apply() -> void:
	if is_inside_tree():
		get_tree().call_group(GROUP, "set_density", density)


func _gpu_ms() -> float:
	if not _vp_rid.is_valid():
		return -1.0
	var t := RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	return t if t > 0.0 else -1.0
