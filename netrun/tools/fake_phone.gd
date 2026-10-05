extends SceneTree
## «Фальшивый телефон»: подключается к очкам (RemotePhoneLink) как приложение и шлёт кадры по сценарию — для живой проверки связи без Android.
## `godot --headless --path netrun -s res://tools/fake_phone.gd -- --url=ws://хост:7420/?token=<токен> [--scenario=idle|chat|call|all] [--callsign=Призрак] [--hold=30]`
## Обычно запускается через tools/fake_phone.sh (тот сам идёт на devbox). Кадры — из tests/fixtures/phone_frames.json, ответы на команды очков — tools/fake_phone_logic.gd.
## Вывод: `<- {json}` — кадр от очков, `-> {json}` — отправленный телефоном. Конец: код 0 (сценарий прошёл, после него --hold секунд слушаем ответы очков)
## или 3 и строка `closed code=… reason=…` (обрыв, нет связи, нет hello_ack). Время считаем по кадрам (`_process`), без sleep.

const Logic := preload("res://tools/fake_phone_logic.gd")
const CONNECT_TIMEOUT_SEC := 10.0
const ACK_TIMEOUT_SEC := 10.0
## После последнего события сценария ещё слушаем очки столько секунд (ответы на команды, resync).
const DEFAULT_HOLD_SEC := 30.0

var _args := {}
var _ws := WebSocketPeer.new()
var _frames: Dictionary = {}
var _clock := 0.0
var _hello_sent := false
var _hello_at := 0.0
var _ack_at := -1.0        # когда пришёл hello_ack (от него считаем сценарий); < 0 — ещё не пришёл
var _events: Array = []    # [{at: абсолютное время, frame}] — сценарий и отложенные ответы, по порядку добавления
var _end_at := 0.0
var _hold := DEFAULT_HOLD_SEC
var _done := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var url := str(_args.get("url", ""))
	if url.is_empty():
		print("[fake-phone] нужен --url=ws://хост:порт/?token=…")
		quit(2)
		_done = true
		return
	_frames = Logic.load_frames()
	if _frames.is_empty():
		print("[fake-phone] нет кадров: ", Logic.FRAMES_PATH)
		quit(2)
		_done = true
		return
	_hold = float(_args.get("hold", DEFAULT_HOLD_SEC))
	var err := _ws.connect_to_url(url)
	if err != OK:
		_fail(0, "connect_to_url error %d" % err)
		return
	print("[fake-phone] подключаюсь к ", url, ", сценарий ", _args.get("scenario", "all"))


func _process(delta: float) -> bool:
	if _done:
		return false
	_clock += delta
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if _clock > CONNECT_TIMEOUT_SEC:
				_fail(0, "connect timeout")
		WebSocketPeer.STATE_OPEN:
			_on_open()
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			_fail(_ws.get_close_code(), _ws.get_close_reason())
	return false


func _on_open() -> void:
	if not _hello_sent:
		_hello_sent = true
		_hello_at = _clock
		var hello: Dictionary = (_frames.get("hello", {"t": "hello", "v": 1}) as Dictionary).duplicate()
		hello["callsign"] = str(_args.get("callsign", hello.get("callsign", "Призрак")))
		_send(hello)
	while _ws.get_available_packet_count() > 0:
		_on_packet(_ws.get_packet())
	if _ack_at < 0.0:
		if _clock - _hello_at > ACK_TIMEOUT_SEC:
			_fail(0, "no hello_ack")
		return
	_fire_due()
	if _clock >= _end_at:
		print("[fake-phone] ok: сценарий закончен")
		_done = true
		_ws.close()
		quit(0)


func _on_packet(packet: PackedByteArray) -> void:
	var text := packet.get_string_from_utf8()
	print("<- ", text)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	var frame: Dictionary = parsed
	if str(frame.get("t", "")) == "hello_ack":
		if _ack_at < 0.0:
			_ack_at = _clock
			var plan: Array = Logic.scenario(str(_args.get("scenario", "all")), _frames)
			for e in plan:
				_events.append({"at": _ack_at + float(e["at"]), "frame": e["frame"]})
			_end_at = _ack_at + Logic.scenario_end(plan) + _hold
		return
	for r in Logic.reply_to(frame, _frames):
		_events.append({"at": _clock + float(r["delay"]), "frame": r["frame"]})
		_end_at = maxf(_end_at, _clock + float(r["delay"]) + 1.0)


## Отправить всё, что подошло по времени (по порядку добавления).
func _fire_due() -> void:
	var rest: Array = []
	for e in _events:
		if float(e["at"]) <= _clock:
			_send(e["frame"])
		else:
			rest.append(e)
	_events = rest


func _send(frame: Dictionary) -> void:
	var text := JSON.stringify(Logic.normalize(frame))
	print("-> ", text)
	_ws.send_text(text)


func _fail(code: int, reason: String) -> void:
	if _done:
		return
	_done = true
	print("closed code=%d reason=%s" % [code, reason])
	quit(3)
