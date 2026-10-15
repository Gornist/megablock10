extends GdUnitTestSuite
## Black ICE по тактам (server/ice/tick_black.gd, ice.md §6.1): сон, пробуждение 6 тактов, охота с пингом раз в 3 такта, захват и ожоги за забег,
## разрыв прыжком, потеря следа и чуткий сон, журнал по тактам.

const LAIR: Array[Vector2i] = [Vector2i(6, 6), Vector2i(7, 6), Vector2i(6, 7), Vector2i(7, 7)]
const HOME := Vector2i(7, 7)
const FAR := Vector2i(13, 7)


func _black(burns: Dictionary = {}, settings: Dictionary = {}) -> TickBlack:
	return TickBlack.new(LAIR, HOME, NodeGrid.new(), settings, burns)


func _ctx(targets: Dictionary, traces: Dictionary = {}, hidden: Dictionary = {}, alarm: int = 0, immune: Dictionary = {}) -> Dictionary:
	return {"targets": targets, "traces": traces, "hidden": hidden, "alarm_level": alarm, "immune": immune}


## Разбудить трассой и дойти до первого такта охоты; возвращает чёрный ICE в охоте.
func _hunting(burns: Dictionary = {}, player: Vector2i = FAR) -> TickBlack:
	var b := _black(burns)
	b.tick(_ctx({"s1": player}, {"s1": 60.0}))
	for i in 6:
		b.tick(_ctx({"s1": player}, {"s1": 60.0}))
	assert_int(b.phase).is_equal(TickBlack.Phase.HUNT)
	return b


func test_спит_пока_trace_ниже_порога_и_просыпается_на_50() -> void:
	var b := _black()
	b.tick(_ctx({"s1": FAR}, {"s1": 49.0}))
	assert_int(b.phase).is_equal(TickBlack.Phase.SLEEP)
	var ev := b.tick(_ctx({"s1": FAR}, {"s1": 50.0}))
	assert_int(b.phase).is_equal(TickBlack.Phase.WAKING)
	assert_str(str(ev[0]["why"])).is_equal("trace")
	assert_int(b.wake_left()).is_equal(6)


func test_пробуждение_шесть_тактов_потом_охота() -> void:
	var b := _black()
	b.tick(_ctx({"s1": FAR}, {"s1": 55.0}))
	var lefts: Array = []
	for i in 5:
		for e in b.tick(_ctx({"s1": FAR}, {"s1": 55.0})):
			if e["kind"] == "wake_step":
				lefts.append(e["left"])
	assert_array(lefts).is_equal([5, 4, 3, 2, 1])
	assert_int(b.phase).is_equal(TickBlack.Phase.WAKING)
	var ev := b.tick(_ctx({"s1": FAR}, {"s1": 55.0}))
	assert_int(b.phase).is_equal(TickBlack.Phase.HUNT)
	assert_str(str(ev[0]["kind"])).is_equal("hunt")


func test_тревога_три_и_мастер_будят_а_один_такт_рядом_нет() -> void:
	var b := _black()
	b.tick(_ctx({"s1": FAR}, {"s1": 0.0}, {}, 2))
	assert_int(b.phase).is_equal(TickBlack.Phase.SLEEP)
	b.tick(_ctx({"s1": FAR}, {"s1": 0.0}, {}, 3))
	assert_int(b.phase).is_equal(TickBlack.Phase.WAKING)
	var m := _black()
	m.wake_by_master()
	m.tick(_ctx({"s1": FAR}))
	assert_str(str(m.journal()[0]["why"])).is_equal("master")
	var n := _black()
	n.tick(_ctx({"s1": Vector2i(9, 7)}))   # на расстоянии 2 от логова
	assert_int(n.phase).is_equal(TickBlack.Phase.SLEEP)
	n.tick(_ctx({"s1": Vector2i(9, 7)}))
	assert_int(n.phase).is_equal(TickBlack.Phase.WAKING)
	assert_str(str(n.journal()[0]["why"])).is_equal("near")


func test_рядом_два_такта_подряд_а_не_суммарно() -> void:
	var b := _black()
	b.tick(_ctx({"s1": Vector2i(9, 7)}))
	b.tick(_ctx({"s1": FAR}))      # ушёл — счётчик сброшен
	b.tick(_ctx({"s1": Vector2i(9, 7)}))
	assert_int(b.phase).is_equal(TickBlack.Phase.SLEEP)


func test_пинг_раз_в_три_такта_цель_с_наибольшим_trace() -> void:
	var b := _black()
	var tr := {"s1": 60.0, "s2": 80.0}
	var tg := {"s1": Vector2i(13, 7), "s2": Vector2i(13, 13)}
	for i in 7:
		b.tick(_ctx(tg, tr))
	var pings := b.journal().filter(func(e): return e["ev"] == "ping")
	assert_int(pings.size()).is_equal(1)   # такт 7 — первый такт охоты, пинг сразу
	assert_str(str(pings[0]["s"])).is_equal("s2")
	for i in 3:
		b.tick(_ctx(tg, tr))
	assert_int(b.journal().filter(func(e): return e["ev"] == "ping").size()).is_equal(2)


func test_идёт_к_засечённой_клетке_по_две_клетки_за_такт() -> void:
	var b := _hunting()
	assert_object(b.cell()).is_equal(Vector2i(9, 7))   # из (7,7) к (13,7): две клетки за такт
	b.tick(_ctx({"s1": FAR}, {"s1": 60.0}))
	assert_object(b.cell()).is_equal(Vector2i(11, 7))


func test_захват_жжёт_за_такт_и_третий_ожог_флэтлайн_с_журналом() -> void:
	var burns := {}
	var b := _hunting(burns, Vector2i(10, 7))   # уже в зоне захвата после шага
	var flat := false
	for i in 6:
		for e in b.tick(_ctx({"s1": Vector2i(10, 7)}, {"s1": 60.0})):
			if e["kind"] == "flatline":
				flat = true
				assert_bool((e["journal"] as Array).any(func(j): return j["ev"] == "wake")).is_true()
		if flat:
			break
	assert_int(int(burns.get("s1", 0))).is_equal(3)
	assert_bool(flat).is_true()


func test_ожоги_копятся_за_забег_между_узлами() -> void:
	var burns := {"s1": 2}   # два ожога из прошлого узла
	var b := _black(burns)
	b.tick(_ctx({"s1": Vector2i(8, 7)}, {"s1": 60.0}))   # будит: рядом с логовом
	var flat := false
	for i in 12:
		for e in b.tick(_ctx({"s1": Vector2i(8, 7)}, {"s1": 60.0})):
			flat = flat or e["kind"] == "flatline"
		if flat:
			break   # дальше узел заканчивает сессию
	assert_bool(flat).is_true()
	assert_int(int(burns["s1"])).is_equal(3)


func test_разрыв_прыжком_дальше_двух_клеток_и_ice_стоит_такт() -> void:
	var burns := {}
	var b := _hunting(burns, Vector2i(10, 7))
	assert_int(int(burns.get("s1", 0))).is_greater_equal(1)
	var held := int(burns["s1"])
	b.on_hop("s1", Vector2i(10, 12))   # дальше 2 клеток
	var at := b.cell()
	b.tick(_ctx({"s1": Vector2i(10, 12)}, {"s1": 60.0}))
	assert_object(b.cell()).is_equal(at)           # стоял такт
	assert_int(int(burns["s1"])).is_equal(held)    # и не жёг
	b.tick(_ctx({"s1": Vector2i(10, 12)}, {"s1": 60.0}))
	assert_object(b.cell()).is_not_equal(at)       # дальше снова идёт


func test_два_пинга_мимо_возврат_в_логово_и_чуткий_сон() -> void:
	var b := _black()
	var tg := {"s1": FAR}
	var tr := {"s1": 60.0}
	for i in 7:
		b.tick(_ctx(tg, tr))
	assert_int(b.phase).is_equal(TickBlack.Phase.HUNT)
	var lost := false
	for i in 12:
		for e in b.tick(_ctx({"s1": Vector2i(13, 14)}, tr, {"s1": true})):   # Призрак: пинги мимо
			lost = lost or e["kind"] == "lost"
		if lost:
			break   # дальше — возврат, а не новая охота при том же trace
	assert_bool(lost).is_true()
	for i in 20:
		b.tick(_ctx(tg, {"s1": 60.0}))   # возврат в логово: опора чуткого сна — 60
		if b.phase == TickBlack.Phase.SLEEP:
			break
	assert_int(b.phase).is_equal(TickBlack.Phase.SLEEP)
	# чуткий сон: порог max(50, 60 + 10) = 70, пробуждение за 3 такта
	b.tick(_ctx(tg, {"s1": 69.0}))
	assert_int(b.phase).is_equal(TickBlack.Phase.SLEEP)
	b.tick(_ctx(tg, {"s1": 70.0}))
	assert_int(b.phase).is_equal(TickBlack.Phase.WAKING)
	assert_int(b.wake_left()).is_equal(3)


## Чёрный ICE после потери следа спит чутко; at_return — trace каждого нетраннера в момент возврата в логово (опоры чуткого сна).
func _sleeping_light(at_return: Dictionary, alarm: int = 0) -> TickBlack:
	var b := _black()
	var here := {}
	var away := {}
	var hid := {}
	for s in at_return:
		here[s] = FAR
		away[s] = Vector2i(13, 14)
		hid[s] = true
	b.wake_by_master()
	for i in 7:
		b.tick(_ctx(here, at_return, {}, alarm))
	assert_int(b.phase).is_equal(TickBlack.Phase.HUNT)
	for i in 12:
		b.tick(_ctx(away, at_return, hid, alarm))   # Призрак далеко: пинги мимо, потеря следа
		if b.phase == TickBlack.Phase.RETURNING:
			break
	for i in 20:
		b.tick(_ctx(here, at_return, {}, alarm))
		if b.phase == TickBlack.Phase.SLEEP:
			break
	assert_int(b.phase).is_equal(TickBlack.Phase.SLEEP)
	return b


func test_чуткий_сон_порог_у_каждого_игрока_свой() -> void:
	var b := _sleeping_light({"s1": 85.0, "s2": 60.0})
	b.tick(_ctx({"s1": FAR, "s2": FAR}, {"s1": 85.0, "s2": 60.0}))   # те же trace — не будит сразу
	assert_int(b.phase).is_equal(TickBlack.Phase.SLEEP)
	b.tick(_ctx({"s1": FAR, "s2": FAR}, {"s1": 94.0, "s2": 69.0}))
	assert_int(b.phase).is_equal(TickBlack.Phase.SLEEP)
	b.tick(_ctx({"s1": FAR, "s2": FAR}, {"s1": 94.0, "s2": 70.0}))   # бывший в узле с 60 — на 70
	assert_int(b.phase).is_equal(TickBlack.Phase.WAKING)
	var c := _sleeping_light({"s1": 85.0})
	c.tick(_ctx({"s1": FAR}, {"s1": 94.0}))
	assert_int(c.phase).is_equal(TickBlack.Phase.SLEEP)
	c.tick(_ctx({"s1": FAR}, {"s1": 95.0}))   # ушедший на 85 будит на 95
	assert_int(c.phase).is_equal(TickBlack.Phase.WAKING)


func test_вошедший_позже_с_высоким_trace_будит_сразу_а_с_низким_по_своей_опоре() -> void:
	var b := _sleeping_light({"s1": 85.0})
	b.tick(_ctx({"s1": FAR, "s3": FAR}, {"s1": 85.0, "s3": 60.0}))   # новичок с 60: опора min(60, 40) = 40 → порог 50
	assert_int(b.phase).is_equal(TickBlack.Phase.WAKING)
	var c := _sleeping_light({"s1": 85.0})
	c.tick(_ctx({"s1": FAR, "s3": FAR}, {"s1": 85.0, "s3": 30.0}))   # вошёл с 30: опора 30 → порог max(50, 40) = 50
	assert_int(c.phase).is_equal(TickBlack.Phase.SLEEP)
	c.tick(_ctx({"s1": FAR, "s3": FAR}, {"s1": 85.0, "s3": 50.0}))
	assert_int(c.phase).is_equal(TickBlack.Phase.WAKING)


func test_тревога_будит_на_переходе_а_не_пока_держится() -> void:
	var b := _sleeping_light({"s1": 10.0}, 3)   # уровень 3 держится всё время потери следа и возврата
	for i in 4:
		b.tick(_ctx({"s1": FAR}, {"s1": 10.0}, {}, 3))
	assert_int(b.phase).is_equal(TickBlack.Phase.SLEEP)   # повторно не будит
	b.tick(_ctx({"s1": FAR}, {"s1": 10.0}, {}, 4))          # переход на 4 — будит
	assert_int(b.phase).is_equal(TickBlack.Phase.WAKING)


func test_пустой_узел_глубокий_сон_порог_50_и_6_тактов() -> void:
	var b := _hunting()
	b.tick(_ctx({}))   # нетраннеров нет
	assert_int(b.phase).is_equal(TickBlack.Phase.SLEEP)
	assert_object(b.cell()).is_equal(HOME)
	b.tick(_ctx({"s1": FAR}, {"s1": 49.0}))
	assert_int(b.phase).is_equal(TickBlack.Phase.SLEEP)   # не 10: порог снова 50
	b.tick(_ctx({"s1": FAR}, {"s1": 50.0}))
	assert_int(b.wake_left()).is_equal(6)                  # и пробуждение 6 тактов, а не 3


func test_призрак_рядом_не_жжётся_ice_нащупывает_клетку() -> void:
	var burns := {}
	var b := _hunting(burns)
	var ghost := Vector2i(b.cell().x + 1, b.cell().y)
	b.tick(_ctx({"s1": ghost}, {"s1": 60.0}, {"s1": true}))
	b.tick(_ctx({"s1": ghost}, {"s1": 60.0}, {"s1": true}))
	assert_int(int(burns.get("s1", 0))).is_equal(0)
	assert_object(b.known_cell()).is_equal(ghost)   # засечка: «нащупал»
	assert_object(b.cell()).is_not_equal(ghost)      # в клетку игрока не входит


func test_грейс_прибытия_не_жжётся() -> void:
	var burns := {}
	var b := _hunting(burns)
	var p := Vector2i(b.cell().x + 1, b.cell().y)
	for i in 3:
		b.tick(_ctx({"s1": p}, {"s1": 60.0}, {}, 0, {"s1": true}))
	assert_int(int(burns.get("s1", 0))).is_equal(0)


func test_прыжок_к_ice_жжёт_даже_скрытого_и_в_грейсе() -> void:
	var burns := {}
	var b := _hunting(burns)
	var p := Vector2i(b.cell().x + 1, b.cell().y)
	b.on_hop("s1", p)   # свой ход рядом с ICE в охоте (С18)
	b.tick(_ctx({"s1": p}, {"s1": 60.0}, {"s1": true}, 0, {"s1": true}))
	assert_int(int(burns.get("s1", 0))).is_equal(1)


func test_журнал_начинается_с_пробуждения_и_без_ходов_во_сне() -> void:
	var b := _black()
	b.on_hop("s2", Vector2i(1, 1))   # спящему ICE ход не пишем
	assert_int(b.journal().size()).is_equal(0)
	b.tick(_ctx({"s1": FAR}, {"s1": 60.0}))
	assert_str(str(b.journal()[0]["ev"])).is_equal("wake")
	# второй цикл: журнал заново, прошлая охота в карточку не попадает
	for i in 7:
		b.tick(_ctx({"s1": FAR}, {"s1": 60.0}))
	b.tick(_ctx({}))   # узел опустел
	b.tick(_ctx({"s2": FAR}, {"s2": 60.0}))
	assert_str(str(b.journal()[0]["ev"])).is_equal("wake")
	assert_array(b.journal().filter(func(e): return e["ev"] == "hop")).is_empty()


# --- виды (ice.md §6.2): по одному наказанию из колонки «Наказывает» ---

func _kind_hunting(kind: String, player: Vector2i = FAR, burns: Dictionary = {}) -> TickBlack:
	var b := TickBlack.new(LAIR, HOME, NodeGrid.new(), {"kind": kind}, burns)
	var wake := 6
	b.wake_by_master()
	for i in wake + 1:
		b.tick(_ctx({"s1": player}, {"s1": 60.0}))
	assert_int(b.phase).is_equal(TickBlack.Phase.HUNT)
	return b


func test_гончая_две_клетки_карты_за_такт_и_сжигает_заряд_на_ожоге() -> void:
	var base := _kind_hunting("")
	var hound := _kind_hunting("hound")
	assert_int(hound.cell().x - HOME.x).is_greater(base.cell().x - HOME.x)   # шаг 4 клетки против 2
	var near := Vector2i(hound.cell().x + 1, hound.cell().y)
	var burns := {}
	var h := _kind_hunting("hound", near, burns)
	var kinds: Array = []
	for e in h.tick(_ctx({"s1": Vector2i(h.cell().x + 1, h.cell().y)}, {"s1": 60.0})):
		kinds.append(e["kind"])
	assert_array(kinds).contains(["burn_charge"])


func test_ворон_пинг_раз_в_два_такта_и_первый_такт_захвата_сносит_а_не_жжёт() -> void:
	var burns := {}
	var r := _kind_hunting("raven", FAR, burns)   # игрок далеко: захвата ещё нет
	assert_int(int(burns.get("s1", 0))).is_equal(0)
	var seen := []
	var near := Vector2i(r.cell().x + 1, r.cell().y)
	# игрок встаёт рядом: первый такт захвата — снос заряда без ожога, второй — ожог
	for e in r.tick(_ctx({"s1": near}, {"s1": 60.0})):
		seen.append(e["kind"])
	assert_array(seen).contains(["strip_charge"])
	assert_int(int(burns.get("s1", 0))).is_equal(0)
	r.tick(_ctx({"s1": near}, {"s1": 60.0}))
	assert_int(int(burns.get("s1", 0))).is_equal(1)
	var pings := r.journal().filter(func(e): return e["ev"] == "ping")
	assert_int(pings.size()).is_greater_equal(2)   # пинг раз в 2 такта чаще, чем раз в 3


func test_кракен_закрывает_выход_пока_не_спит() -> void:
	var k := TickBlack.new(LAIR, HOME, NodeGrid.new(), {"kind": "kraken"})
	assert_bool(k.exit_locked()).is_false()
	k.wake_by_master()
	k.tick(_ctx({"s1": FAR}))
	assert_bool(k.exit_locked()).is_true()
	var base := TickBlack.new(LAIR, HOME, NodeGrid.new())
	base.wake_by_master()
	base.tick(_ctx({"s1": FAR}))
	assert_bool(base.exit_locked()).is_false()


func test_скорпион_в_кольце_ограничивает_прыжок_одной_клеткой() -> void:
	var s := TickBlack.new(LAIR, HOME, NodeGrid.new(), {"kind": "scorpion"})
	assert_float(s.hop_limit_at(HOME + Vector2i(2, 0))).is_equal(0.0)   # спит — ограничения нет
	s.wake_by_master()
	s.tick(_ctx({"s1": FAR}))
	assert_float(s.hop_limit_at(s.cell() + Vector2i(3, 0))).is_equal(1.5)   # в 4 клетках 1 м (2 клетки карты)
	assert_float(s.hop_limit_at(s.cell() + Vector2i(5, 0))).is_equal(0.0)


func test_лич_на_ожоге_снимает_расшифровку() -> void:
	var l := _kind_hunting("lich", Vector2i(10, 7))
	var kinds: Array = []
	for i in 2:
		for e in l.tick(_ctx({"s1": Vector2i(l.cell().x + 1, l.cell().y)}, {"s1": 60.0})):
			kinds.append(e["kind"])
	assert_array(kinds).contains(["strip_decrypt"])


func test_неизвестный_вид_это_базовый() -> void:
	assert_bool(TickBlack.kind_settings("???").is_empty()).is_true()
	assert_array(TickBlack.KINDS).contains(["", "hound", "kraken", "raven", "scorpion", "lich"])
