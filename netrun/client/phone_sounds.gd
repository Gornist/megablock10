class_name PhoneSounds
extends Node
## Звуки телефона в гарнитуре: приложение просит их кадром sound{kind} (RemotePhoneLink.sound_requested), играет их этот узел.
## Рингтон и дозвон — петлёй до `stop`, сообщение — один раз. Отдельной шины нет, всё идёт в Master.

## Громкость в дБ. Рингтон в телефоне громкий и протяжный, в гарнитуре он звучит у самого уха — приглушён;
## дозвон тише рингтона (это «гудок в трубке», а не вызов); сообщение — короткий акцент поверх остального звука игры.
const VOLUME_DB_RING := -6.0
const VOLUME_DB_RINGBACK := -9.0
const VOLUME_DB_MESSAGE := -6.0

const RING_STREAM_PATH := "res://client/audio/phone/cyberpunk_ring.mp3"
const RINGBACK_STREAM_PATH := "res://client/audio/phone/cp77_dial_tone.mp3"
const MESSAGE_STREAM_PATH := "res://client/audio/phone/cyberpunk_message.mp3"

var _ring: AudioStreamPlayer
var _ringback: AudioStreamPlayer
var _message: AudioStreamPlayer
## Собственные флаги «играет»: в headless-прогоне аудио-драйвер Dummy, и `playing` у плеера там не гарантирован.
var _on := {"ring": false, "ringback": false, "message": false}
var _link: RemotePhoneLink


func _init() -> void:
	_ring = _make_player(RING_STREAM_PATH, true, VOLUME_DB_RING)
	_ringback = _make_player(RINGBACK_STREAM_PATH, true, VOLUME_DB_RINGBACK)
	_message = _make_player(MESSAGE_STREAM_PATH, false, VOLUME_DB_MESSAGE)
	_message.finished.connect(func() -> void: _on["message"] = false)


## Подписаться на запросы звука связи; повторный bind (в том числе null) отписывает прежнюю связь.
func bind(link: RemotePhoneLink) -> void:
	if _link != null and _link.sound_requested.is_connected(play):
		_link.sound_requested.disconnect(play)
	_link = link
	if _link != null:
		_link.sound_requested.connect(play)


func play(kind: String) -> void:
	match kind:
		"ring":
			_stop_loop("ringback")
			if not _on["ring"]:
				_start("ring", _ring)
		"ringback":
			_stop_loop("ring")
			if not _on["ringback"]:
				_start("ringback", _ringback)
		"message":
			_start("message", _message)
		"stop":
			_stop_loop("ring")
			_stop_loop("ringback")
		_:
			pass  # неизвестный вид — игнор: приложение новее очков не должно ломать связь


func is_playing(kind: String) -> bool:
	return _on.get(kind, false)


func _start(kind: String, player: AudioStreamPlayer) -> void:
	_on[kind] = true
	if player.is_inside_tree():  # узел вне дерева (тест без сцены) играть не может — состояние всё равно ведём
		player.play()


func _stop_loop(kind: String) -> void:
	_on[kind] = false
	var player := _ring if kind == "ring" else _ringback
	player.stop()


func _make_player(path: String, looped: bool, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var stream := load(path) as AudioStreamMP3
	if stream != null:
		# load() отдаёт общий ресурс: петля включается на копии, иначе зациклится и одиночный звук.
		stream = stream.duplicate() as AudioStreamMP3
		stream.loop = looped
		player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player
