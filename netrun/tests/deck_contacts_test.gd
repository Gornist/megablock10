extends GdUnitTestSuite
## Блок КОНТАКТЫ на вкладке ЗВОНКИ (DeckCalls): строка на контакт телефона с «ПОЗВОНИТЬ» (позывной уходит в start_call), блока нет без контактов,
## кнопки недоступны при звонке и без связи, список обновляется по contacts_changed, показываем не больше MAX_CONTACTS.

const T0 := 1_700_000_000.0


## Фиктивная связь со своим списком контактов, переключаемой «связью с телефоном» и записью вызовов start_call.
class ContactsLink extends FakePhoneLink:
	var list: Array = []
	var online := true
	var started: Array = []

	func contacts() -> Array:
		return list.duplicate(true)

	func is_online() -> bool:
		return online

	func set_online(on: bool) -> void:
		online = on
		online_changed.emit(on)

	func set_contacts(titles: Array) -> void:
		list = titles.map(func(t): return {"key": "KEY_" + str(t), "title": str(t)})
		contacts_changed.emit()

	func start_call(peer_id: String) -> void:
		started.append(peer_id)
		super.start_call(peer_id)


var _calls: DeckCalls


func _setup(titles: Array, online: bool = true) -> ContactsLink:
	var link := ContactsLink.new(T0, false)
	link.auto_reply = false
	link.online = online
	link.set_contacts(titles)
	_calls = auto_free(DeckCalls.new())
	add_child(_calls)
	_calls.bind(link)
	await _settle()
	return link


func _settle(frames: int = 3) -> void:
	for i in frames:
		await get_tree().process_frame


func test_no_contacts_means_no_block() -> void:
	await _setup([])
	assert_int(_calls.contact_row_count()).is_equal(0)
	assert_bool(DeckUi.texts(_calls).has("КОНТАКТЫ")).is_false()


func test_three_contacts_are_three_rows_and_calling_starts_a_call_by_callsign() -> void:
	var link := await _setup(["ЛИС", "ВОБЛА", "ШЕРШЕНЬ"])
	assert_int(_calls.contact_row_count()).is_equal(3)
	assert_bool(DeckUi.texts(_calls).has("КОНТАКТЫ")).is_true()
	var names := DeckUi.texts(_calls)
	for n in ["ЛИС", "ВОБЛА", "ШЕРШЕНЬ"]:
		assert_bool(names.has(n)).is_true()
	var requested: Array = []
	_calls.log_call_requested.connect(func(p): requested.append(p))
	var btn: MbButton = _calls.contact_call_buttons()[1]
	assert_bool(btn.disabled).is_false()
	btn.click()
	assert_array(link.started).is_equal(["ВОБЛА"])
	assert_array(requested).is_equal(["ВОБЛА"])
	assert_str(link.call_state()["phase"]).is_equal(PhoneLink.PHASE_OUTGOING)


func test_contact_buttons_are_disabled_during_a_call() -> void:
	var link := await _setup(["ЛИС", "ВОБЛА"])
	link.incoming_call("ЛИС")
	_calls.refresh()   # панель зовёт refresh() по call_changed; вкладка здесь одна, без панели
	await _settle()
	assert_int(_calls.contact_row_count()).is_equal(2)
	for b in _calls.contact_call_buttons():
		assert_bool((b as MbButton).disabled).is_true()
	link.decline_call()
	_calls.refresh()
	await _settle()
	for b in _calls.contact_call_buttons():
		assert_bool((b as MbButton).disabled).is_false()


func test_contact_buttons_are_disabled_when_the_phone_is_offline() -> void:
	var link := await _setup(["ЛИС", "ВОБЛА"], false)
	for b in _calls.contact_call_buttons():
		assert_bool((b as MbButton).disabled).is_true()
	link.set_online(true)
	_calls.apply_online()
	await _settle()
	for b in _calls.contact_call_buttons():
		assert_bool((b as MbButton).disabled).is_false()


func test_contacts_changed_rebuilds_the_block() -> void:
	var link := await _setup(["ЛИС"])
	assert_int(_calls.contact_row_count()).is_equal(1)
	link.set_contacts(["ЛИС", "ВОБЛА", "ШЕРШЕНЬ"])
	await _settle()
	assert_int(_calls.contact_row_count()).is_equal(3)
	link.set_contacts([])
	await _settle()
	assert_int(_calls.contact_row_count()).is_equal(0)
	assert_bool(DeckUi.texts(_calls).has("КОНТАКТЫ")).is_false()


func test_rebind_unsubscribes_from_the_previous_link() -> void:
	var old_link := await _setup(["ЛИС"])
	var new_link := ContactsLink.new(T0, false)
	new_link.set_contacts(["ВОБЛА", "ШЕРШЕНЬ"])
	_calls.bind(new_link)
	await _settle()
	assert_int(_calls.contact_row_count()).is_equal(2)
	old_link.set_contacts(["А", "Б", "В", "Г"])   # старая связь больше не слушается
	await _settle()
	assert_int(_calls.contact_row_count()).is_equal(2)


func test_more_than_the_limit_shows_only_the_first_eight() -> void:
	var titles: Array = []
	for i in 11:
		titles.append("КОНТАКТ%d" % i)
	await _setup(titles)
	assert_int(DeckCalls.MAX_CONTACTS).is_equal(8)
	assert_int(_calls.contact_row_count()).is_equal(8)
	assert_bool(DeckUi.texts(_calls).has("КОНТАКТ7")).is_true()
	assert_bool(DeckUi.texts(_calls).has("КОНТАКТ8")).is_false()
