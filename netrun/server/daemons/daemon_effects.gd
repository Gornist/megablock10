class_name DaemonEffects
extends RefCounted
## Реестр «имя эффекта → обработчик». Обработчик: func(def, session, target, now) -> Dictionary.
## Успех: {"ok": true, "event": {...}}, отказ: {"ok": false, "error": "код"}.
## Новый демон с существующим эффектом — только JSON; новый эффект — одна функция и register().

var _handlers: Dictionary = {}


func _init() -> void:
	register("GHOST", _ghost)
	register("JITTER", _jitter)
	register("EXTRACT_SHARD", _extract_shard)


func register(effect: String, handler: Callable) -> void:
	_handlers[effect] = handler


func has_effect(effect: String) -> bool:
	return _handlers.has(effect)


func run(def: DaemonDef, session: DaemonSession, target: Dictionary, now: float) -> Dictionary:
	return _handlers[def.effect].call(def, session, target, now)


## Невидимость для ICE на duration_sec: флаг на сессии.
func _ghost(def: DaemonDef, session: DaemonSession, _target: Dictionary, now: float) -> Dictionary:
	var dur := float(def.params.get("duration_sec", 20.0))
	session.ghost_until = maxf(session.ghost_until, now + dur)
	return {"ok": true, "event": {"type": "ghost", "daemon": def.id, "until": session.ghost_until}}


## trace замирает на duration_sec.
func _jitter(def: DaemonDef, session: DaemonSession, _target: Dictionary, now: float) -> Dictionary:
	var dur := float(def.params.get("duration_sec", 15.0))
	session.trace.freeze(now, dur)
	return {"ok": true, "event": {"type": "jitter", "daemon": def.id, "duration": dur}}


## Цель: слот хранилища {"id", "type": "shard", "tier"}. Только событие и запись в добычу сессии:
## предмет настоящим образом переходит владельцу позже, операцией Моста.
func _extract_shard(def: DaemonDef, session: DaemonSession, target: Dictionary, _now: float) -> Dictionary:
	if target.get("type") != "shard" or str(target.get("id", "")) == "":
		return {"ok": false, "error": "bad_target"}
	if int(target.get("tier", 1)) > def.tier:
		return {"ok": false, "error": "tier_too_high"}
	if session.has_looted(str(target["id"])):
		return {"ok": false, "error": "already_taken"}
	session.loot.append({"id": str(target["id"]), "type": "shard", "tier": int(target.get("tier", 1))})
	return {"ok": true, "event": {"type": "extract_shard", "daemon": def.id, "item": str(target["id"])}}
