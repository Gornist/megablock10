class_name DeckFeedback
extends Node3D
## Отклик деки на события телефона: входящее сообщение — короткий импульс левого контроллера и тихий сигнал; входящий звонок — серия
## импульсов и рингтон, пока звонит. Звук синтезируется один раз при старте (AudioStreamWAV из нескольких тонов), готовых аудиофайлов нет.
## Звучит из позиции деки (AudioStreamPlayer3D на якоре руки). Нет вибрации или звука на устройстве — молча, без ошибок.
## Голос самого звонка (микрофон и динамики) здесь не обрабатывается: это следующий этап.

const SAMPLE_RATE := 22050
## Сообщение: два коротких тона вверх.
const MESSAGE_NOTES := [[880.0, 0.07], [1175.0, 0.09]]
## Новая добыча от другого игрока (К5б): один тихий тон вверх и слабый импульс — внимание на ДОБЫЧУ, без рингтона.
const LOOT_NOTES := [[988.0, 0.09]]
const LOOT_PULSE_AMP := 0.2
const LOOT_DB := -20.0
const MESSAGE_PULSE_AMP := 0.35
const MESSAGE_PULSE_S := 0.05
## Рингтон: два коротких тона дважды, потом тишина до конца периода; на тот же период — серия импульсов.
const RING_NOTES := [[660.0, 0.16], [880.0, 0.16], [660.0, 0.16], [880.0, 0.16]]
const RING_PERIOD_S := 2.2
const RING_BURST := 3          ## импульсов в серии
const RING_GAP_S := 0.22       ## между импульсами серии
const RING_PULSE_AMP := 0.7
const RING_PULSE_S := 0.12
const CONFIRM_PULSE_AMP := 0.4   ## ответили на звонок / звонок закончился
const CONFIRM_PULSE_S := 0.08
const MESSAGE_DB := -14.0
const RING_DB := -8.0

## Куда уходят импульсы вместо контроллера (тесты): Callable(hand: String ("left" | "right"), amplitude: float, seconds: float).
var pulse_sink: Callable = Callable()
## Сколько импульсов запрошено и сколько раз играл сигнал (для проверки).
var pulse_count := 0
var message_beeps := 0
var loot_cues := 0
var ring_starts := 0

var rig: XRRig
var link: PhoneLink
var _phase := PhoneLink.PHASE_IDLE
var _ringing := false
var _ring_clock := 0.0
var _ring_idx := 0
var _msg_player: AudioStreamPlayer3D
var _loot_player: AudioStreamPlayer3D
var _ring_player: AudioStreamPlayer3D


func _ready() -> void:
	_msg_player = _player(make_tone_stream(MESSAGE_NOTES, 0.02, 0.0, false), MESSAGE_DB)
	_loot_player = _player(make_tone_stream(LOOT_NOTES, 0.0, 0.0, false), LOOT_DB)
	_ring_player = _player(make_tone_stream(RING_NOTES, 0.05, RING_PERIOD_S, true), RING_DB)
	set_process(false)


func bind(r: XRRig, l: PhoneLink) -> void:
	if link != null:
		link.message_received.disconnect(_on_message)
		link.call_changed.disconnect(_on_call)
		_stop_ring()
	rig = r
	link = l
	_phase = PhoneLink.PHASE_IDLE
	if link != null:
		link.message_received.connect(_on_message)
		link.call_changed.connect(_on_call)
		_phase = link.call_state()["phase"]
		if _phase == PhoneLink.PHASE_INCOMING:
			_start_ring()


func is_ringing() -> bool:
	return _ringing


## Момент (с от начала звонка) индекса-го импульса звонка: серии по RING_BURST импульсов раз в RING_PERIOD_S.
static func ring_pulse_time(index: int) -> float:
	return floorf(float(index) / RING_BURST) * RING_PERIOD_S + float(index % RING_BURST) * RING_GAP_S


## Импульс контроллера: hand — "left" | "right". Без очков и без трекера не делает ничего.
func pulse(hand: String, amplitude: float, seconds: float) -> void:
	pulse_count += 1
	if pulse_sink.is_valid():
		pulse_sink.call(hand, amplitude, seconds)
		return
	if rig == null or not rig.xr_active:
		return
	var h: XRController3D = rig.left_hand if hand == "left" else rig.right_hand
	if h != null:
		h.trigger_haptic_pulse("haptic", 0.0, amplitude, seconds, 0.0)


## Сигнал о новом предмете в ГРУЗе от другого игрока: тихий тон и короткий импульс левой руки (с декой на запястье).
func loot_cue() -> void:
	loot_cues += 1
	pulse("left", LOOT_PULSE_AMP, MESSAGE_PULSE_S)
	_play(_loot_player)


func _on_message(_thread_id: String, msg: Dictionary) -> void:
	if bool(msg.get("mine", false)):
		return
	message_beeps += 1
	pulse("left", MESSAGE_PULSE_AMP, MESSAGE_PULSE_S)
	_play(_msg_player)


func _on_call(state: Dictionary) -> void:
	var phase: String = state["phase"]
	if phase == _phase:
		return
	var was := _phase
	_phase = phase
	if phase == PhoneLink.PHASE_INCOMING:
		_start_ring()
		return
	if was == PhoneLink.PHASE_INCOMING:
		_stop_ring()
	if phase == PhoneLink.PHASE_IN_CALL or (was == PhoneLink.PHASE_IN_CALL and phase == PhoneLink.PHASE_IDLE):
		pulse("left", CONFIRM_PULSE_AMP, CONFIRM_PULSE_S)


func _start_ring() -> void:
	_ringing = true
	ring_starts += 1
	_ring_clock = 0.0
	_ring_idx = 0
	set_process(true)
	_play(_ring_player)
	_step_ring(0.0)


func _stop_ring() -> void:
	_ringing = false
	set_process(false)
	if _ring_player != null:
		_ring_player.stop()


func _process(delta: float) -> void:
	if _ringing:
		_step_ring(delta)


## Часы звонка: все импульсы, чьё время наступило, уходят (так же зовут тесты, без настоящего времени).
func _step_ring(delta: float) -> void:
	_ring_clock += delta
	while ring_pulse_time(_ring_idx) <= _ring_clock:
		pulse("left", RING_PULSE_AMP, RING_PULSE_S)
		_ring_idx += 1


func _play(p: AudioStreamPlayer3D) -> void:
	if p != null and p.is_inside_tree():
		p.play()


func _player(stream: AudioStream, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.unit_size = 4.0
	p.max_distance = 3.0
	add_child(p)
	return p


## Сигнал из тонов: notes — [[Гц, секунды], …], между тонами тишина gap_s; всё дополняется тишиной до total_s (0 — без хвоста).
## loop — зациклить (рингтон). Огибающая с коротким нарастанием и спадом, чтобы не щёлкало; тон — синус с мягкой второй гармоникой.
static func make_tone_stream(notes: Array, gap_s: float, total_s: float, loop: bool) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	for n in notes:
		var hz: float = n[0]
		var count := int(float(n[1]) * SAMPLE_RATE)
		for i in count:
			var t := float(i) / SAMPLE_RATE
			var env := minf(1.0, minf(t / 0.004, (float(count - i) / SAMPLE_RATE) / 0.02))
			samples.append((sin(TAU * hz * t) * 0.8 + sin(TAU * hz * 2.0 * t) * 0.15) * env * 0.5)
		for i in int(gap_s * SAMPLE_RATE):
			samples.append(0.0)
	var want := int(total_s * SAMPLE_RATE)
	while samples.size() < want:
		samples.append(0.0)
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SAMPLE_RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w
