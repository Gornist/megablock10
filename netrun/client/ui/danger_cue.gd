class_name DangerCue
extends Node3D
## Опасное — в центре зрения, а не на деке (ice.md §8 «Правило П6», 16.10: «в панике на деку не смотрят»): метка у центра на 1–2 с, свой звук на каждый вид,
## на ожог ещё красная вспышка по краям зрения и сильная вибрация. Три сигнала: пробуждение Black ICE («ЧЁРНЫЙ ЛЁД 6…» обратным счётом по тактам),
## ожог («ОЖОГ 2/3»), рост уровня тревоги («ТРЕВОГА 2»); четвёртый (П8) — сработал Датчик («ЛУЧ → ТРЕВОГА +5»). Дека их только повторяет. Крепится к камере (rig.camera). Нет очков, звука или вибрации — молча.

const DIST := 0.9            ## расстояние метки от глаз, м
const DROP := 0.04           ## метка чуть ниже оси взгляда, чтобы не закрывать цель по центру
const SHOW_SEC := 1.6        ## сколько держится метка
const WAKE_SHOW_SEC := 1.2   ## метка отсчёта живёт до следующего такта
const FADE_SEC := 0.35       ## плавное гашение в конце
const FLASH_HALF_FOV := 0.95   ## половина горизонтального поля зрения по умолчанию (очки, нет обычной камеры), рад
const BURN_PULSE_AMP := 1.0
const BURN_PULSE_S := 0.35
const ALARM_PULSE_AMP := 0.5
const ALARM_PULSE_S := 0.15
const WAKE_PULSE_AMP := 0.25
const WAKE_PULSE_S := 0.05
const SENSOR_PULSE_AMP := 0.6
const SENSOR_PULSE_S := 0.12
const SENSOR_DB := -8.0
const WAKE_DB := -10.0
const ALARM_DB := -8.0
const BURN_DB := -4.0
## Звуки (тоны через DeckFeedback.make_tone_stream): отсчёт — короткий сухой щелчок, тревога — два тона вверх, ожог — низкий удар и тон.
const WAKE_NOTES := [[330.0, 0.06]]
const ALARM_NOTES := [[523.0, 0.1], [698.0, 0.14]]
const BURN_NOTES := [[110.0, 0.22], [82.0, 0.28]]
## Датчик: резкий высокий щелчок-«чирик» (две короткие ноты вниз) — отличается и от тревоги (вверх), и от ожога (низкий).
const SENSOR_NOTES := [[1175.0, 0.05], [880.0, 0.09]]

## Куда уходят импульсы (по умолчанию — ничего; сцена подключает DeckFeedback.pulse): Callable(hand: String, amplitude: float, seconds: float).
var pulse_sink: Callable = Callable()
## Сколько раз показана метка каждого вида — для проверки.
var shown := {"wake": 0, "burn": 0, "alarm": 0, "sensor": 0}

var _label: Label3D
var _flash: MeshInstance3D
var _flash_mat: ShaderMaterial
var _left := 0.0
var _flash_left := 0.0
var _players: Dictionary = {}
var _wake_last := -1
var _burn_last := 0
var _alarm_last := 0


## Половина горизонтального поля зрения камеры, рад: на плоском экране считается по fov и соотношению сторон окна; в очках (рантайм сам задаёт поле) и без камеры — FLASH_HALF_FOV.
func _half_fov() -> float:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or cam.get_viewport() == null or cam.get_viewport().use_xr:
		return FLASH_HALF_FOV
	var size := cam.get_viewport().get_visible_rect().size
	if size.y <= 0.0:
		return FLASH_HALF_FOV
	var half_v := deg_to_rad(cam.fov) * 0.5
	if cam.keep_aspect == Camera3D.KEEP_HEIGHT:
		return atan(tan(half_v) * size.x / size.y)
	return half_v


func _ready() -> void:
	_label = Label3D.new()
	_label.font_size = 96
	_label.pixel_size = 0.0007
	_label.position = Vector3(0.0, -DROP, -DIST)
	_label.no_depth_test = true
	_label.render_priority = 100
	_label.visible = false
	Label3DSharp.apply(_label)
	add_child(_label)
	_flash_mat = AssetMaterials.burn_flash_material(_half_fov())   # шейдер и цвет — у Blender; клиент меняет только strength
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.material = _flash_mat
	_flash = MeshInstance3D.new()
	_flash.mesh = quad
	_flash.position = Vector3(0.0, 0.0, -0.24)
	_flash.visible = false
	_flash.extra_cull_margin = 16.0
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash)
	_players["wake"] = _player(DeckFeedback.make_tone_stream(WAKE_NOTES, 0.0, 0.0, false), WAKE_DB)
	_players["alarm"] = _player(DeckFeedback.make_tone_stream(ALARM_NOTES, 0.02, 0.0, false), ALARM_DB)
	_players["burn"] = _player(DeckFeedback.make_tone_stream(BURN_NOTES, 0.0, 0.0, false), BURN_DB)
	_players["sensor"] = _player(DeckFeedback.make_tone_stream(SENSOR_NOTES, 0.0, 0.0, false), SENSOR_DB)
	set_process(false)


## Пробуждение Black ICE: left — тактов до конца пробуждения (bw состояния); при смене числа — метка «ЧЁРНЫЙ ЛЁД n…» и щелчок. 0 и меньше — отсчёт кончился.
func wake_count(left: int) -> void:
	if left <= 0:
		_wake_last = -1
		return
	if left == _wake_last:
		return
	_wake_last = left
	shown["wake"] += 1
	_show("ЧЁРНЫЙ ЛЁД %d…" % left, AssetMaterials.layer("hud_bad"), WAKE_SHOW_SEC, "wake")
	_pulse("right", WAKE_PULSE_AMP, WAKE_PULSE_S)


## Ожоги за забег (поле burn состояния): рост числа — «ОЖОГ n/limit», красная вспышка краёв, удар и сильная вибрация обеими руками.
func burns(count: int, limit: int = 3) -> void:
	if count <= _burn_last:
		_burn_last = count   # счётчик ушёл вниз — новый забег: следующий ожог снова покажется
		return
	_burn_last = count
	shown["burn"] += 1
	_show("ОЖОГ %d/%d" % [count, limit], AssetMaterials.layer("hud_bad"), SHOW_SEC, "burn")
	_flash_left = AssetMaterials.BURN_FLASH_SEC
	_flash_mat.set_shader_parameter("half_fov", _half_fov())
	_flash_mat.set_shader_parameter("strength", AssetMaterials.BURN_FLASH_START)
	_flash.visible = true
	_pulse("left", BURN_PULSE_AMP, BURN_PULSE_S)
	_pulse("right", BURN_PULSE_AMP, BURN_PULSE_S)


## Уровень тревоги узла сменился: рост — «ТРЕВОГА n» (1 «насторожен» не кричит — метка с уровня 2 и выше), спад только запоминается.
func alarm_level(level: int) -> void:
	var up := level > _alarm_last
	_alarm_last = level
	if not up or level < 2:
		return
	shown["alarm"] += 1
	_show("ТРЕВОГА %d" % level, AssetMaterials.layer("hud_bad"), SHOW_SEC, "alarm")
	_pulse("left", ALARM_PULSE_AMP, ALARM_PULSE_S)


## Сработал Датчик на этого игрока (поле `sf` состояния): метка «ЛУЧ → ТРЕВОГА +n» в центре зрения, щелчок и импульс. Вспышку самого луча даёт SensorView.flash.
func sensor_fired(alarm_add: int) -> void:
	shown["sensor"] += 1
	_show("ЛУЧ → ТРЕВОГА +%d" % alarm_add, AssetMaterials.layer("hud_bad"), SHOW_SEC, "sensor")
	_pulse("left", SENSOR_PULSE_AMP, SENSOR_PULSE_S)
	_pulse("right", SENSOR_PULSE_AMP, SENSOR_PULSE_S)


## Новый забег или другой узел-хозяин: счётчики событий сбросить (ожоги идут за забег, но клиент — новый на каждый забег).
func reset() -> void:
	_wake_last = -1
	_burn_last = 0
	_alarm_last = 0


func is_showing() -> bool:
	return _left > 0.0


func shown_text() -> String:
	return _label.text if _label != null and _label.visible else ""


func _show(text: String, color: Color, seconds: float, sound: String) -> void:
	_label.text = text
	_label.modulate = color
	_label.visible = true
	_left = seconds
	var p: AudioStreamPlayer3D = _players.get(sound)
	if p != null and p.is_inside_tree():
		p.play()
	set_process(true)


func _pulse(hand: String, amp: float, seconds: float) -> void:
	if pulse_sink.is_valid():
		pulse_sink.call(hand, amp, seconds)


func _process(delta: float) -> void:
	_step(delta)


## Шаг времени: метка гаснет за FADE_SEC в конце, вспышка линейно сходит на нет.
func _step(delta: float) -> void:
	if _left > 0.0:
		_left -= delta
		var a := clampf(_left / FADE_SEC, 0.0, 1.0)
		var c := _label.modulate
		c.a = a
		_label.modulate = c
		if _left <= 0.0:
			_label.visible = false
	if _flash_left > 0.0:
		_flash_left -= delta
		_flash_mat.set_shader_parameter("strength", AssetMaterials.BURN_FLASH_START * clampf(_flash_left / AssetMaterials.BURN_FLASH_SEC, 0.0, 1.0))
		if _flash_left <= 0.0:
			_flash.visible = false
	if _left <= 0.0 and _flash_left <= 0.0:
		set_process(false)


func _player(stream: AudioStream, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.unit_size = 4.0
	p.max_distance = 3.0
	add_child(p)
	return p
