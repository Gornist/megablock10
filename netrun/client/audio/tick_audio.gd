class_name TickAudio
extends Node
## Такт слышно (time-and-movement.md, п. 4 разбора П3): тихий пульс на каждом такте узла (по смене tk.n) и щелчки «тиканья» перед шагом ближайшего ICE,
## которые к концу окна учащаются. Звучит через тот же ToneSynth, что гул ICE и trace; громкости и тона — AudioSettings["tick"].
## Берёт данные у RemoteTracks (tk, намерения ICE, часы сервера) и у рига (клетка игрока) каждый кадр сам; в плоской сборке и в тестах не создаётся.

var settings: Dictionary
var beat := TickBeat.new()
## Кто сейчас звучит: "" — тишина; возраст звука, с.
var kind := ""
var age := 0.0
var pulses := 0   ## сколько пульсов было (для тестов и журнала)
var clicks_made := 0
## Стингеры состояний Стража («?» / «!» / «…», IceStingers): сколько раз играл каждый вид; alarm — тревожный слой на пульсе (какой-то ICE в Поиске).
var stingers := IceStingers.new()
var stings := {}
var alarm := false

var _last_n := -1
var _remote: RemoteTracks
var _rig: Node3D
var _player: AudioStreamPlayer
var _synth: ToneSynth
var _playback: AudioStreamGeneratorPlayback


func _init(custom: Dictionary = {}) -> void:
	settings = AudioSettings.merged(custom)


## Откуда брать такт и клетку игрока.
func bind(remote: RemoteTracks, rig: Node3D) -> void:
	_remote = remote
	_rig = rig


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = settings["sample_rate"]
	gen.buffer_length = 0.15
	_synth = ToneSynth.new(gen.mix_rate)
	_synth.noise = 0.05
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()


func pulse() -> void:
	pulses += 1
	_start("pulse")


## Стингер состояния Стража (IceStingers.KIND_*) вместо пульса этого такта: тот же голос, звук и значок над ICE приходят в один кадр.
func sting(sting_kind: String) -> void:
	stings[sting_kind] = int(stings.get(sting_kind, 0)) + 1
	_start(sting_kind)


func click() -> void:
	clicks_made += 1
	_start("click")


func _start(k: String) -> void:
	kind = k
	age = 0.0


## Один кадр: смена такта → пульс; ближайший ICE шагнёт → щелчки с нарастающей частотой; затем озвучить текущий звук.
func _process(delta: float) -> void:
	if _remote != null and _rig != null:
		poll(delta, Time.get_ticks_msec() / 1000.0)
	_voice(delta)


## Логика кадра без звука: по снимку RemoteTracks решает, когда пульс и щелчки (в тестах — вручную, local_now подаёт тест).
func poll(delta: float, local_now: float) -> void:
	var tk := _remote.tick_info()
	if tk.is_empty():
		beat.reset()
		stingers.reset()
		_last_n = -1
		alarm = false
		return
	var s := ""
	var n := int(tk.get("n", -1))
	if n != _last_n:   # новый такт: переходы стадий ICE с прошлого (первый снимок — без звука, только запомнить)
		_last_n = n
		s = stingers.observe(_remote.intents(), n)
		alarm = IceStingers.any_search(_remote.intents())
	if beat.observe(tk):
		if s != "":
			sting(s)
		else:
			pulse()
	var cell := NodeGrid.cell_of(_rig.global_position)
	var frac := TickBeat.window_fraction(tk, _remote.clock.server_time(local_now))
	var soon := TickBeat.ice_steps_soon(_remote.intents(), cell)
	var rate := TickBeat.click_rate(soon, frac, int(tk.get("inh", 0)) == 1)
	if beat.clicks(delta, rate) > 0:
		click()


func _voice(delta: float) -> void:
	if _synth == null:
		return
	if kind == "":
		_player.volume_db = -80.0
		_synth.gain = 0.0
		_synth.fill(_playback)
		return
	age += delta
	var p := AudioParams.tick_params(kind, age, settings, alarm)
	if not p["active"]:
		kind = ""
		_synth.gain = 0.0
	else:
		_player.volume_db = p["volume_db"]
		_synth.hz = p["hz"]
		_synth.gain = p["gain"]
	_synth.fill(_playback)
