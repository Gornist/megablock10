class_name RemoteTracks
extends RefCounted
## Чужое в узле, как его видит клиент: другие нетраннеры и ICE, у каждого — StateBuffer, общие часы сервера — ServerClock.
## Чистая логика (без сцены): сцена зовёт on_state / on_avatars по приходу пакетов и ice_pose / avatar_pose каждый кадр.

## Задержка показа. Аватары приходят 20 раз/с, ICE — 10 раз/с (интервал 0.1 с), поэтому ICE нужен запас побольше.
const AVATAR_DELAY := 0.1
const ICE_DELAY := 0.15

var clock := ServerClock.new()
var ice: Dictionary = {}      # id ICE -> StateBuffer
var avatars: Dictionary = {}  # id аватара (строкой) -> StateBuffer


## Снимок узла (WorldMsg.STATE): ICE. Без метки времени `k` (старые тесты) — местное время: смещение будет нулевым.
func on_state(state: Dictionary, local_now: float) -> void:
	var k := _stamp(state, local_now)
	for d in state.get("ice", []):
		var id := str(d["id"])
		if not ice.has(id):
			ice[id] = StateBuffer.new()
		var p: Array = d["p"]
		var f: Array = d["f"]
		(ice[id] as StateBuffer).push(k, Vector3(p[0], p[1], p[2]), atan2(-float(f[0]), -float(f[1])))


## Позиции других аватаров (WorldMsg.AVATARS). Возвращает id, которых в списке больше нет (вышли из узла).
func on_avatars(msg: Dictionary, local_now: float) -> Array:
	var k := _stamp(msg, local_now)
	var seen := {}
	for e in msg.get("a", []):
		var id := str(int(e[0]))
		seen[id] = true
		if not avatars.has(id):
			avatars[id] = StateBuffer.new()
		(avatars[id] as StateBuffer).push(k, Vector3(float(e[1]), 0.0, float(e[2])))
	var gone: Array = []
	for id in avatars.keys():
		if not seen.has(id):
			gone.append(id)
			avatars.erase(id)
	return gone


func ice_pose(id: String, local_now: float) -> Dictionary:
	var b: StateBuffer = ice.get(id)
	return b.sample(clock.render_time(local_now, ICE_DELAY)) if b != null else {}


func avatar_pose(id: String, local_now: float) -> Dictionary:
	var b: StateBuffer = avatars.get(id)
	return b.sample(clock.render_time(local_now, AVATAR_DELAY)) if b != null else {}


func _stamp(msg: Dictionary, local_now: float) -> float:
	var k := float(msg.get("k", local_now))
	clock.observe(k, local_now)
	return k
