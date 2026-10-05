extends GdUnitTestSuite
## Звуки телефона в гарнитуре (client/phone_sounds.gd): рингтон и дозвон петлёй, сообщение один раз;
## запросы приходят кадром sound{kind} через RemotePhoneLink.sound_requested. Сеть не нужна: кадры подаются в on_frame.

var _sounds: PhoneSounds
var _link: RemotePhoneLink


func before_test() -> void:
	_sounds = PhoneSounds.new()
	add_child(_sounds)
	_link = RemotePhoneLink.new()
	_sounds.bind(_link)


func after_test() -> void:
	_sounds.free()


func _sound(kind: String) -> void:
	_link.on_frame({"t": "sound", "kind": kind})


func test_ring_играет() -> void:
	_sound("ring")
	assert_bool(_sounds.is_playing("ring")).is_true()
	assert_bool(_sounds.is_playing("ringback")).is_false()


func test_ringback_вместо_ring_останавливает_рингтон() -> void:
	_sound("ring")
	_sound("ringback")
	assert_bool(_sounds.is_playing("ring")).is_false()
	assert_bool(_sounds.is_playing("ringback")).is_true()


func test_ring_вместо_ringback_останавливает_дозвон() -> void:
	_sound("ringback")
	_sound("ring")
	assert_bool(_sounds.is_playing("ringback")).is_false()
	assert_bool(_sounds.is_playing("ring")).is_true()


func test_stop_гасит_обе_петли() -> void:
	_sound("ring")
	_sound("stop")
	assert_bool(_sounds.is_playing("ring")).is_false()
	_sound("ringback")
	_sound("stop")
	assert_bool(_sounds.is_playing("ringback")).is_false()


func test_message_не_останавливает_петлю() -> void:
	_sound("ring")
	_sound("message")
	assert_bool(_sounds.is_playing("ring")).is_true()
	assert_bool(_sounds.is_playing("message")).is_true()


func test_stop_не_обрывает_одиночное() -> void:
	_sound("message")
	_sound("stop")
	assert_bool(_sounds.is_playing("message")).is_true()


func test_повторный_ring_не_перезапускает_петлю() -> void:
	_sound("ring")
	var player := _sounds.get_child(0) as AudioStreamPlayer
	await get_tree().create_timer(0.1).timeout
	var before := player.get_playback_position()
	_sound("ring")
	assert_bool(_sounds.is_playing("ring")).is_true()
	# позиция не сбросилась в начало (в Dummy-драйвере она может быть 0 — тогда проверка вырождается, но не ломается)
	assert_float(player.get_playback_position()).is_greater_equal(before)


func test_неизвестный_kind_ничего_не_меняет() -> void:
	_sound("ring")
	_sounds.play("whistle")
	_sounds.play("")
	assert_bool(_sounds.is_playing("ring")).is_true()
	assert_bool(_sounds.is_playing("ringback")).is_false()
	assert_bool(_sounds.is_playing("message")).is_false()
	assert_bool(_sounds.is_playing("whistle")).is_false()


func test_повторный_bind_отписывает_прежнюю_связь() -> void:
	var other := RemotePhoneLink.new()
	_sounds.bind(other)
	_sound("ring")  # старая связь больше не управляет
	assert_bool(_sounds.is_playing("ring")).is_false()
	other.on_frame({"t": "sound", "kind": "ring"})
	assert_bool(_sounds.is_playing("ring")).is_true()


func test_bind_null_отписывает() -> void:
	_sounds.bind(null)
	_sound("ring")
	assert_bool(_sounds.is_playing("ring")).is_false()


func test_петли_зациклены_а_сообщение_нет() -> void:
	var loops := {}
	for c in _sounds.get_children():
		var s := (c as AudioStreamPlayer).stream as AudioStreamMP3
		assert_object(s).is_not_null()
		loops[s.loop] = int(loops.get(s.loop, 0)) + 1
	assert_int(loops.get(true, 0)).is_equal(2)
	assert_int(loops.get(false, 0)).is_equal(1)
	# порядок детей: ring, ringback, message
	assert_bool(((_sounds.get_child(0) as AudioStreamPlayer).stream as AudioStreamMP3).loop).is_true()
	assert_bool(((_sounds.get_child(1) as AudioStreamPlayer).stream as AudioStreamMP3).loop).is_true()
	assert_bool(((_sounds.get_child(2) as AudioStreamPlayer).stream as AudioStreamMP3).loop).is_false()
