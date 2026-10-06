class_name PhoneVoice
extends Node
## Голос телефона в очках: телефон просит `voice{on,rate}` (RemotePhoneLink.voice_requested) — узел открывает микрофон и динамик, отвечает `voice_ready`,
## шлёт кадры микрофона каждые ≈20 мс и играет звук собеседника (docs/netrun-phone-link.md, «Голос»).
##
## Микрофон — `AudioServer.get_input_frames` (а не шина с AudioEffectCapture: у той задержка микрофона Godot растёт, godot #80173): забираем всё накопленное,
## приводим к моно и частоте связи (PhoneVoiceDsp) и копим. Кадры уходят НЕПРЕРЫВНО по счётчику дельт — телефон возвращается на свой звук, если кадров нет
## дольше 2 с, поэтому при пустом входе идут нулевые отсчёты. Звук собеседника — AudioStreamGenerator на частоте связи в Master.

## Динамики Pico рядом с микрофоном, а шумоподавления в Godot нет: собеседник слышит своё эхо. Мера — дуплексное приглушение: пока звук собеседника
## громче DUCK_PEER_RMS (и ещё DUCK_HOLD_MS после этого), вместо микрофона уходит тишина (кадры всё равно идут). Для замера эха — HALF_DUPLEX := false.
const HALF_DUPLEX := true
const DUCK_PEER_RMS := 0.02
const DUCK_HOLD_MS := 150

const CHUNK_MS := 20
## За один такт отправляется не больше стольких кусков (после подвисания кадра не выстреливаем очередью); остаток времени отбрасывается.
const MAX_CHUNKS_PER_TICK := 5
## Очередь воспроизведения не длиннее этого (и буфер генератора): задержку не копим, лишний кадр собеседника отбрасывается.
const PLAYBACK_QUEUE_S := 0.2
## Накопитель микрофона длиннее этого — лишнее старое отбрасывается (иначе задержка микрофона растёт, если отправка отстаёт).
const MIC_PENDING_MAX_S := 0.3
const PERMISSION := "RECORD_AUDIO"

## Ответ очков телефону отправлен: on — открыт ли голос, reason — "ok" | "no_permission" | "no_input" | "bad_rate".
signal ready_sent(on: bool, reason: String)

var _link: RemotePhoneLink
var _active := false
var _rate := 0
var _pending := PackedFloat32Array()     # микрофон, уже моно на частоте связи, ещё не отправленный
var _acc := 0.0                          # накопленное время до очередного куска, с
var _duck_left_ms := 0.0
var _last_seq := -1                      # последний принятый seq собеседника; -1 — кадров ещё не было
var _permission_asked := false
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback

var _sent := 0
var _received := 0
var _lost := 0
var _late := 0
var _overflow := 0
var _mic_dropped := 0
var _ducked_ms := 0


func _ready() -> void:
	set_process(_active)
	if get_tree().has_signal("on_request_permissions_result"):
		get_tree().connect("on_request_permissions_result", _on_permission_result)


func _exit_tree() -> void:
	if _active:
		_stop()


## Подписаться на запросы голоса и кадры собеседника; повторный bind (в том числе null) отписывает прежнюю связь и гасит голос.
func bind(link: RemotePhoneLink) -> void:
	if _link != null:
		if _link.voice_requested.is_connected(_on_voice_requested):
			_link.voice_requested.disconnect(_on_voice_requested)
		if _link.voice_frame_received.is_connected(_on_peer_frame):
			_link.voice_frame_received.disconnect(_on_peer_frame)
	if _active:
		_stop()
	_link = link
	if _link != null:
		_link.voice_requested.connect(_on_voice_requested)
		_link.voice_frame_received.connect(_on_peer_frame)


func is_active() -> bool:
	return _active


func stats() -> Dictionary:
	return {"active": _active, "rate": _rate, "sent": _sent, "received": _received, "lost": _lost, "late": _late,
		"overflow": _overflow, "ducked_ms": _ducked_ms, "mic_dropped": _mic_dropped}


# ---------------------------------------------------------------- источники и приёмники звука (в тестах переопределяются)

## Выдано ли разрешение на микрофон. Не-Android — всегда. На Android — просим один раз и пока отвечаем «нет»: ответ придёт позже сигналом дерева.
func _permission_ok() -> bool:
	if OS.get_name() != "Android":
		return true
	for p in OS.get_granted_permissions():
		if str(p).ends_with(PERMISSION):
			return true
	if not _permission_asked:
		_permission_asked = true
		OS.request_permission(PERMISSION)
	return false


## Открыть вход микрофона; false — входа нет (нет устройства или сервер звука отказал).
func _input_ready() -> bool:
	return AudioServer.set_input_device_active(true) == OK


func _input_close() -> void:
	AudioServer.set_input_device_active(false)


func _input_rate() -> int:
	return int(AudioServer.get_input_mix_rate())


## Всё накопленное на входе, но не больше max_frames отсчётов (стерео, частота `_input_rate`).
func _pull_input(max_frames: int) -> PackedVector2Array:
	var n := mini(AudioServer.get_input_frames_available(), max_frames)
	if n <= 0:
		return PackedVector2Array()
	return AudioServer.get_input_frames(n)


## Сколько отсчётов ещё влезет в очередь воспроизведения.
func _playback_free_frames() -> int:
	return _playback.get_frames_available() if _playback != null else 0


func _playback_push(stereo: PackedVector2Array) -> void:
	if _playback != null:
		_playback.push_buffer(stereo)


# ---------------------------------------------------------------- включение и выключение

func _on_voice_requested(on: bool, rate: int) -> void:
	if _active:
		_stop()   # повторное включение с другой частотой — заново
	if not on:
		return
	if rate <= 0:
		_answer(false, "bad_rate")
		return
	if not _permission_ok():
		_answer(false, "no_permission")
		return
	if not _input_ready():
		_answer(false, "no_input")
		return
	_start(rate)
	_answer(true, "ok")


func _answer(on: bool, reason: String) -> void:
	if _link != null:
		_link.send_voice_ready(on)
	ready_sent.emit(on, reason)


func _start(rate: int) -> void:
	_rate = rate
	_active = true
	_pending = PackedFloat32Array()
	_acc = 0.0
	_duck_left_ms = 0.0
	_last_seq = -1
	_sent = 0
	_received = 0
	_lost = 0
	_late = 0
	_overflow = 0
	_mic_dropped = 0
	_ducked_ms = 0
	_pull_input(1 << 20)   # то, что накопилось до включения, — старое: выбрасываем
	_make_player(rate)
	set_process(true)


func _stop() -> void:
	_active = false
	set_process(false)
	_input_close()
	_pending = PackedFloat32Array()
	_acc = 0.0
	_duck_left_ms = 0.0
	if _player != null:
		_player.stop()
		_player.queue_free()
		_player = null
	_playback = null


func _make_player(rate: int) -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = rate
	gen.buffer_length = PLAYBACK_QUEUE_S
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	add_child(_player)
	if _player.is_inside_tree():   # узел вне дерева (тест без сцены) играть не может
		_player.play()
		_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


## Разрешение на микрофон пришло позже запроса: если телефон всё ещё ждёт голос — включаем.
func _on_permission_result(permission: String, granted: bool) -> void:
	if granted and permission.ends_with(PERMISSION) and not _active and _link != null and _link.voice_active():
		_on_voice_requested(true, _link.voice_rate())


# ---------------------------------------------------------------- микрофон → телефон

func _process(delta: float) -> void:
	advance(delta)


## Один такт: забрать вход и отправить положенное число кусков. Отдельно от `_process`, чтобы тест вёл время сам.
func advance(delta: float) -> void:
	if not _active:
		return
	_collect_input()
	_duck_left_ms = maxf(_duck_left_ms - delta * 1000.0, 0.0)
	var chunk_s := float(CHUNK_MS) / 1000.0
	_acc += delta
	var sent_now := 0
	while _acc >= chunk_s and sent_now < MAX_CHUNKS_PER_TICK:
		_acc -= chunk_s
		sent_now += 1
		_send_chunk()
	if sent_now >= MAX_CHUNKS_PER_TICK:
		_acc = 0.0   # подвисание: отставшее время не долг, иначе поток кусков уйдёт вперёд часов


func _collect_input() -> void:
	var in_rate := _input_rate()
	var frames := _pull_input(maxi(in_rate, 1) >> 1)   # не больше полсекунды за такт
	if frames.is_empty() or in_rate <= 0:
		return
	var mono := PhoneVoiceDsp.resample_linear(PhoneVoiceDsp.stereo_to_mono_float(frames), in_rate, _rate)
	_pending.append_array(mono)
	var cap := int(float(_rate) * MIC_PENDING_MAX_S)
	if _pending.size() > cap:
		_mic_dropped += _pending.size() - cap
		_pending = _pending.slice(_pending.size() - cap)


func _send_chunk() -> void:
	var n := PhoneVoiceCodec.samples_per_chunk(_rate, CHUNK_MS)
	if n <= 0:
		return
	var take := mini(_pending.size(), n)
	var real := _pending.slice(0, take)
	_pending = _pending.slice(take)   # забираем в любом случае: приглушённый микрофон не копится в задержку
	var pcm: PackedByteArray
	if HALF_DUPLEX and _duck_left_ms > 0.0:
		pcm = PhoneVoiceDsp.silence_pcm16(n)
		_ducked_ms += CHUNK_MS
	else:
		pcm = PhoneVoiceDsp.float_to_pcm16(real)
		pcm.append_array(PhoneVoiceDsp.silence_pcm16(n - take))   # реальных отсчётов не хватило — добиваем нулями, поток не рвём
	if _link != null and _link.send_voice_chunk(pcm):
		_sent += 1


# ---------------------------------------------------------------- телефон → динамик

func _on_peer_frame(seq: int, pcm: PackedByteArray) -> void:
	if not _active:
		return
	if _last_seq >= 0:
		var diff := (seq - _last_seq) & 0xFFFFFFFF   # разность по модулю 2^32: «позже» — меньше половины круга
		if diff == 0 or diff >= 0x80000000:
			_late += 1
			return
		_lost += diff - 1
	_last_seq = seq
	_received += 1
	if PhoneVoiceDsp.rms_pcm16(pcm) > DUCK_PEER_RMS:
		_duck_left_ms = float(DUCK_HOLD_MS)
	var stereo := PhoneVoiceDsp.pcm16_to_stereo(pcm)
	if stereo.is_empty():
		return
	if _playback_free_frames() < stereo.size():   # очередь уже у потолка: этот кадр потеряем, но задержку не копим
		_overflow += 1
		return
	_playback_push(stereo)
