class_name DaemonService
extends RefCounted
## «Применить <демон> к <цели>»: проверка (демон известен, в деке сессии, не на перезарядке,
## цель допустима для эффекта) и результат-событие для рассылки. Время — снаружи.

const DATA_DIR := "res://data/daemons"

var effects := DaemonEffects.new()
var _defs: Dictionary = {}


## Загружает все *.json из каталога; возвращает число загруженных.
func load_dir(dir_path: String = DATA_DIR) -> int:
	var count := 0
	for file in DirAccess.get_files_at(dir_path):
		if not file.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir_path.path_join(file)))
		if parsed is Dictionary and add_def(DaemonDef.from_dict(parsed)):
			count += 1
	return count


func add_def(def: DaemonDef) -> bool:
	if def == null or not effects.has_effect(def.effect):
		return false
	_defs[def.id] = def
	return true


func get_def(id: String) -> DaemonDef:
	return _defs.get(id)


func apply(session: DaemonSession, daemon_id: String, target: Dictionary, now: float) -> Dictionary:
	var def: DaemonDef = _defs.get(daemon_id)
	if def == null:
		return {"ok": false, "error": "unknown_daemon"}
	if not session.deck.has(daemon_id):
		return {"ok": false, "error": "not_in_deck"}
	if session.cooldown_left(daemon_id, now) > 0.0:
		return {"ok": false, "error": "cooldown"}
	var result := effects.run(def, session, target, now)
	if result.get("ok", false):
		session.start_cooldown(daemon_id, now, def.cooldown_sec)
	return result
