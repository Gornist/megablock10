class_name BeatStats
extends RefCounted
## Состояние очков (P6): окно кадров между отправками и чистые функции «пора слать», связь по RTT, заряд.
## Окно копит кадры; take() выдаёт средний FPS и худший кадр за окно и начинает новое.

## Сервер принимает состояние не чаще, чем раз в (период × эту долю): клиент шлёт «примерно раз в период», с дрожанием.
const SERVER_GAP_FACTOR := 0.8
## RTT, ниже которого связь считается 100, и выше которого — 0 (мс); между ними линейно.
const RTT_GOOD_MS := 20
const RTT_BAD_MS := 300

var _frames := 0
var _sum := 0.0
var _worst := 0.0


func add_frame(delta_sec: float) -> void:
	if delta_sec <= 0.0:
		return
	_frames += 1
	_sum += delta_sec
	_worst = maxf(_worst, delta_sec)


## {fps: средний (целый, 0 — кадров не было), worst_ms: худший кадр (мс, целый)}. Окно обнуляется.
func take() -> Dictionary:
	var out := {"fps": avg_fps(_frames, _sum), "worst_ms": int(roundf(_worst * 1000.0))}
	_frames = 0
	_sum = 0.0
	_worst = 0.0
	return out


static func avg_fps(frames: int, total_sec: float) -> int:
	if frames <= 0 or total_sec <= 0.0:
		return 0
	return int(roundf(frames / total_sec))


## Пора слать: ещё ни разу (last_ms < 0) или прошёл период. Часы назад (now < last) — не слать.
static func due(now_ms: int, last_ms: int, period_ms: int) -> bool:
	if last_ms < 0:
		return true
	return now_ms - last_ms >= period_ms


## Минимальный промежуток на стороне сервера для периода клиента.
static func server_gap_ms(period_sec: float) -> int:
	return int(period_sec * 1000.0 * SERVER_GAP_FACTOR)


## Качество связи 0–100 по RTT (мс); отрицательный (нет данных) — -1.
static func link_from_rtt(rtt_ms: int) -> int:
	if rtt_ms < 0:
		return -1
	if rtt_ms <= RTT_GOOD_MS:
		return 100
	if rtt_ms >= RTT_BAD_MS:
		return 0
	return int(roundf(100.0 * float(RTT_BAD_MS - rtt_ms) / float(RTT_BAD_MS - RTT_GOOD_MS)))


## Заряд из значения, которое вернул датчик: целое 0–100 или -1 (нет датчика / мусор).
static func battery_pct(v: Variant) -> int:
	if v == null or not (v is int or v is float):
		return -1
	var p := int(roundf(float(v)))
	return p if p >= 0 and p <= 100 else -1


## Тело сообщения состояния: поля без значения (-1) не кладутся.
static func make_fields(terminal: String, battery: int, charging: Variant, fps: int, worst_ms: int, rtt_ms: int) -> Dictionary:
	var f := {"term": terminal, "fps": fps, "worst": worst_ms}
	if battery >= 0:
		f["bat"] = battery
	if charging is bool:
		f["chg"] = charging
	if rtt_ms >= 0:
		f["rtt"] = rtt_ms
	return f
