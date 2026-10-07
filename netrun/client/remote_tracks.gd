class_name RemoteTracks
extends RefCounted
## Чужое в узле, как его видит клиент: другие нетраннеры и ICE, у каждого — StateBuffer, общие часы сервера — ServerClock.
## Чистая логика (без сцены): сцена зовёт on_state / on_avatars по приходу пакетов и ice_pose / avatar_pose каждый кадр.

## Задержка показа. Аватары приходят 20 раз/с, ICE — 10 раз/с (интервал 0.1 с), поэтому ICE нужен запас побольше.
const AVATAR_DELAY := 0.1
const ICE_DELAY := 0.15

## Шаг тактового ICE между клетками: плавно за столько секунд (time-and-movement.md Т5), а не рывок на клетку.
const STEP_SEC := 0.4
## Изменение позиции / поворота меньше этого шагом не считается (шум округления).
const _STEP_EPS := 0.01

var clock := ServerClock.new()
var ice: Dictionary = {}      # id ICE -> StateBuffer
var avatars: Dictionary = {}  # id аватара (строкой) -> StateBuffer
var poses: Dictionary = {}    # id аватара (строкой) -> AvatarPose из последнего пакета; нет записи — в пакете позы не было (или мусор)
var _intents: Array = []      # намерения ICE из последнего снимка (TickForecast.parse_intents); в realtime пусто
var _tick: Dictionary = {}    # поле tk последнего снимка: n, at, win, inh, mv; в realtime пусто
var _steps: Dictionary = {}   # id тактового ICE -> {from_p, to_p, from_yaw, to_yaw, t0}: идущий шаг между клетками


## Снимок узла (WorldMsg.STATE): ICE. Без метки времени `k` (старые тесты) — местное время: смещение будет нулевым.
## Тактовый Soft ICE (в записи есть клетка `c`) идёт между клетками плавно за STEP_SEC по местным часам; Black ICE и realtime — по буферу.
func on_state(state: Dictionary, local_now: float) -> void:
	var k := _stamp(state, local_now)
	var list: Array = state.get("ice", [])
	_intents = TickForecast.parse_intents(list)
	var tk: Variant = state.get("tk")
	_tick = (tk as Dictionary).duplicate() if tk is Dictionary else {}
	for d in list:
		var id := str(d["id"])
		if not ice.has(id):
			ice[id] = StateBuffer.new()
		var p: Array = d["p"]
		var f: Array = d["f"]
		var pos := Vector3(p[0], p[1], p[2])
		var yaw := atan2(-float(f[0]), -float(f[1]))
		(ice[id] as StateBuffer).push(k, pos, yaw)
		if d.has("c") and int(d.get("b", 0)) == 0:
			_step_target(id, pos, yaw, local_now)


## Намерения ICE из последнего снимка: словари {c, d, st, nc, nd, sc, black} (клетки — Vector2i). В realtime — пусто.
func intents() -> Array:
	return _intents


## Поле tk последнего снимка: n — номер такта, at — его время (часы сервера), win — окно, inh — вдох, mv — ход принят. В realtime — пусто.
func tick_info() -> Dictionary:
	return _tick


## Секунды до такта по окну (по часам сервера), округлённые вверх; не меньше 0. Нет тактов — 0.
func window_left(local_now: float) -> int:
	if _tick.is_empty():
		return 0
	var left := float(_tick.get("at", 0.0)) + float(_tick.get("win", 0.0)) - clock.server_time(local_now)
	return maxi(ceili(left - 0.0001), 0)


## ICE исчез из снимка (игрок в другом узле): забыть его позу и шаг.
func forget_ice(id: String) -> void:
	ice.erase(id)
	_steps.erase(id)


func _step_target(id: String, pos: Vector3, yaw: float, local_now: float) -> void:
	var s: Dictionary = _steps.get(id, {})
	if s.is_empty():
		_steps[id] = {"from_p": pos, "to_p": pos, "from_yaw": yaw, "to_yaw": yaw, "t0": local_now}
		return
	var to_p: Vector3 = s["to_p"]
	if to_p.distance_to(pos) <= _STEP_EPS and absf(angle_difference(float(s["to_yaw"]), yaw)) <= _STEP_EPS:
		return   # цель та же: идущий шаг не трогаем
	var cur := _step_pose(s, local_now)   # новая цель — от того места, где ICE сейчас, чтобы не дёргать
	_steps[id] = {"from_p": cur["p"], "to_p": pos, "from_yaw": cur["yaw"], "to_yaw": yaw, "t0": local_now}


static func _step_pose(s: Dictionary, local_now: float) -> Dictionary:
	var k := clampf((local_now - float(s["t0"])) / STEP_SEC, 0.0, 1.0)
	return {"p": (s["from_p"] as Vector3).lerp(s["to_p"], k), "yaw": lerp_angle(float(s["from_yaw"]), float(s["to_yaw"]), k)}


## Позиции других аватаров (WorldMsg.AVATARS). Возвращает id, которых в списке больше нет (вышли из узла).
func on_avatars(msg: Dictionary, local_now: float) -> Array:
	var k := _stamp(msg, local_now)
	var seen := {}
	for e in msg.get("a", []):
		var id := str(int(e[0]))
		seen[id] = true
		if not avatars.has(id):
			avatars[id] = StateBuffer.new()
		var jump := int(e[3]) if e.size() > 3 else 0  # счётчик скачков (телепортов) аватара
		(avatars[id] as StateBuffer).push(k, Vector3(float(e[1]), 0.0, float(e[2])), 0.0, jump)
		var pose := AvatarPose.decode(e[4]) if e.size() > 4 else null
		if pose != null:
			poses[id] = pose
		else:
			poses.erase(id)
	var gone: Array = []
	for id in avatars.keys():
		if not seen.has(id):
			gone.append(id)
			avatars.erase(id)
			poses.erase(id)
	return gone


func ice_pose(id: String, local_now: float) -> Dictionary:
	if _steps.has(id):
		return _step_pose(_steps[id], local_now)
	var b: StateBuffer = ice.get(id)
	return b.sample(clock.render_time(local_now, ICE_DELAY)) if b != null else {}


func avatar_pose(id: String, local_now: float) -> Dictionary:
	var b: StateBuffer = avatars.get(id)
	return b.sample(clock.render_time(local_now, AVATAR_DELAY)) if b != null else {}


func _stamp(msg: Dictionary, local_now: float) -> float:
	var k := float(msg.get("k", local_now))
	clock.observe(k, local_now)
	return k
