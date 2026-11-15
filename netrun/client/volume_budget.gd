class_name VolumeBudget
extends Node
## Регулятор плотности облаков по GPU-времени кадра (план «волюметрик», шаг «volume_budget_ms»). `[render] volume_budget_ms = N` — потолок GPU-времени кадра, мс
## (при 90 Гц бюджет кадра 11,1 мс, потолок ≈ 10,5); 0 — регулятор выключен (по умолчанию).
## Схема (15.11, вместо среднего за окно со ступенями ×0,8/×1,1):
##  1. Кольцо RING_SIZE валидных кадров GPU (gpu_ms > 0; невалидные не пишутся). Меньше MIN_VALID валидных — плотность не трогается.
##  2. Раз в EVAL_SEC — оценка: p95 кольца → цель `target`. p95 > потолка — цель падает на K_DOWN·(p95 − потолок)/потолок; p95 > потолка + HARD_MS — сразу ×0,75;
##     p95 < потолка − MARGIN_MS — растёт на UP_STEP за оценку. EMA кадра (`ema_ms`) — для журнала и отладки.
##     После каждой смены цели кольцо очищается: его кадры сняты при прежней плотности, а задержка кольца (≈1,3 с) давала автоколебания (цикл 0,4↔0,65 на модели сцены).
##  3. Видимая плотность `density` каждый кадр догоняет цель: вниз с постоянной TAU_DOWN, вверх с TAU_UP (скачка нет).
##     В группу `volume_clouds` (VolumeCloud.set_density) уходит, только если сдвинулась больше чем на APPLY_EPS.
##  4. Облако, вошедшее в сцену после снижения, спрашивает current_density() через группу `volume_budget` (VolumeCloud._sync_budget).
## Плотность — множитель к префиксу точек (ЛОД по расстоянию остаётся): падение выкидывает хвост перемешанного массива, вид редеет равномерно.

signal changed(density: float)   ## видимая плотность применена к облакам
signal targeted(target: float)   ## цель изменилась (после оценки)

const RING_SIZE := 120
const MIN_VALID := 30
const EVAL_SEC := 0.25
const EMA_ALPHA := 0.1
const K_DOWN := 0.6
const HARD_MS := 1.5
const HARD_FACTOR := 0.75
## Запас восстановления: порог = потолок − MARGIN_MS. Не меньше 0,4 мс: база сцены на очках ≈ 9,7 мс при потолке 10,5 — порог ниже базы никогда не пускал плотность назад.
const MARGIN_MS := 0.4
const UP_STEP := 0.05
const TAU_DOWN := 0.3
const TAU_UP := 2.0
const APPLY_EPS := 0.005
const MIN_DENSITY := 0.25
const MAX_DENSITY := 1.0
const GROUP := "volume_clouds"
const BUDGET_GROUP := "volume_budget"

## Потолок GPU-времени кадра, мс; 0 — регулятор не работает.
var limit_ms := 0.0
## Видимая плотность (то, что применено к облакам).
var density := MAX_DENSITY
## Цель, к которой плотность плавно идёт.
var target := MAX_DENSITY
## EMA GPU-времени кадра, мс (−1 — кадров ещё не было).
var ema_ms := -1.0

var _shown := MAX_DENSITY   # непрерывная плотность каждого кадра; в density (и в облака) уходит, когда отошла от неё больше чем на APPLY_EPS
var _ring := PackedFloat32Array()
var _ring_n := 0       # сколько валидных кадров в кольце (до RING_SIZE)
var _ring_i := 0       # куда писать следующий
var _acc := 0.0
var _vp_rid := RID()


func _ready() -> void:
	add_to_group(BUDGET_GROUP)
	_ring.resize(RING_SIZE)
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)


func _process(delta: float) -> void:
	feed(delta, _gpu_ms())


## Текущая видимая плотность — для облака, вошедшего в сцену позже (1 — если регулятор выключен).
func current_density() -> float:
	return density if limit_ms > 0.0 else MAX_DENSITY


## Один кадр: delta (с), gpu_ms (≤ 0 — рендерер не отдал). Вынесено из _process, чтобы тесты гнали время вручную.
func feed(delta: float, gpu_ms: float) -> void:
	if limit_ms <= 0.0:
		return
	if _ring.size() != RING_SIZE:
		_ring.resize(RING_SIZE)
	if gpu_ms > 0.0:
		_ring[_ring_i] = gpu_ms
		_ring_i = (_ring_i + 1) % RING_SIZE
		_ring_n = mini(_ring_n + 1, RING_SIZE)
		ema_ms = gpu_ms if ema_ms < 0.0 else lerpf(ema_ms, gpu_ms, EMA_ALPHA)
	_acc += delta
	if _acc >= EVAL_SEC:
		_acc = 0.0
		if _ring_n >= MIN_VALID:
			var next := next_target(target, p95(_ring.slice(0, _ring_n)), limit_ms)
			if next != target:
				target = next
				_ring_n = 0   # кадры кольца сняты при прежней плотности: решать по ним дальше — раскачка (замкнутая модель: цикл 0,4↔0,65); копим заново
				_ring_i = 0
				targeted.emit(target)
	_shown = follow(_shown, target, delta)
	if absf(_shown - target) < 0.001:
		_shown = target   # без хвоста экспоненты: доходит до цели и до 1,0 точно
	if absf(_shown - density) > APPLY_EPS or (_shown != density and (_shown == MAX_DENSITY or _shown == MIN_DENSITY)):
		density = _shown
		_apply()
		changed.emit(density)


## 95-й процентиль кольца (метод ближайшего ранга); пусто — −1.
static func p95(ring: PackedFloat32Array) -> float:
	if ring.is_empty():
		return -1.0
	var sorted := ring.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(0.95 * sorted.size()) - 1, 0, sorted.size() - 1)]


## Новая цель по p95 GPU-времени: выше потолка — на долю превышения (жёстко выше потолка + HARD_MS — ×0,75), ниже потолка на MARGIN_MS — шаг вверх; нет данных (< 0) — без изменений.
static func next_target(current: float, p95_ms: float, limit: float) -> float:
	if limit <= 0.0 or p95_ms < 0.0:
		return current
	if p95_ms > limit + HARD_MS:
		return maxf(MIN_DENSITY, current * HARD_FACTOR)
	if p95_ms > limit:
		return maxf(MIN_DENSITY, current - K_DOWN * (p95_ms - limit) / limit)
	if p95_ms < limit - MARGIN_MS:
		return minf(MAX_DENSITY, current + UP_STEP)
	return current


## Видимая плотность догоняет цель экспонентой: вниз с постоянной TAU_DOWN, вверх с TAU_UP (не зависит от частоты кадров).
static func follow(shown: float, goal: float, delta: float) -> float:
	var tau := TAU_DOWN if goal < shown else TAU_UP
	return lerpf(shown, goal, 1.0 - exp(-maxf(delta, 0.0) / tau))


func _apply() -> void:
	if is_inside_tree():
		get_tree().call_group(GROUP, "set_density", density)


func _gpu_ms() -> float:
	if not _vp_rid.is_valid():
		return -1.0
	return RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
