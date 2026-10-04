class_name DaemonSession
extends RefCounted
## Состояние нетраннера, которое трогают демоны: дека, перезарядки, флаги, добыча.
## Время подаётся снаружи (секунды).

var deck: Array[String] = []  # id демонов, выбранных в деку
var trace: TraceMeter
var ghost_until: float = -INF  # ICE читает is_ghost(now)
var loot: Array[Dictionary] = []  # добыча забега (события; настоящую выдачу делает Мост)
var _ready_at: Dictionary = {}  # id демона -> время конца перезарядки
## Что дека показывает игроку (ev deck): RAM забега (session.data.ram Моста; пока Мост её не пишет — DEFAULT_RAM и ram_default), свойства
## рабочих демонов {id -> {cells, prot}} и добыча (шарды и добытые демоны) с эдди. Заполняет сервер мира из документов Моста; на игру не влияет.
const DEFAULT_RAM := 6
var ram: int = DEFAULT_RAM
var ram_default := true
var deck_meta: Dictionary = {}
var loot_view: Array = []
var loot_eddies: int = 0
## Ключ нетраннера (session.data.runner) и остывание узлов для него (runner.data.breach_cooldown: узел -> мс Unix конца): панель взлома по ним
## пишет «ОСТЫВАЕТ». Заполняет сервер мира из документов Моста; пока Мост не ответил — пусто, остывания нет.
var runner_key := ""
var breach_cooldown: Dictionary = {}


func _init(deck_ids: Array = [], meter: TraceMeter = null) -> void:
	for d in deck_ids:
		deck.append(str(d))
	trace = meter if meter != null else TraceMeter.new()


func is_ghost(now: float) -> bool:
	return now < ghost_until


## Имена активных эффектов (как `DaemonEffect` в :rules) для Моста: правило сигнала СБ читает их из session.world.effects.
## Сейчас у сервера мира есть только GHOST; TIMESKEW и BLACKOUT добавятся вместе со своими обработчиками.
func active_effects(now: float) -> Array:
	var out: Array = []
	if is_ghost(now):
		out.append("GHOST")
	return out


## Сколько секунд ещё действует эффект демона (0 — не действует): GHOST и JITTER. Остальные эффекты окна не имеют.
func active_left(effect: String, now: float) -> float:
	match effect:
		"GHOST":
			return maxf(0.0, ghost_until - now)
		"JITTER":
			return trace.frozen_left(now)
	return 0.0


func cooldown_left(daemon_id: String, now: float) -> float:
	return maxf(0.0, float(_ready_at.get(daemon_id, -INF)) - now)


func start_cooldown(daemon_id: String, now: float, seconds: float) -> void:
	_ready_at[daemon_id] = now + seconds


func has_looted(item_id: String) -> bool:
	for l in loot:
		if l.get("id") == item_id:
			return true
	return false
