class_name BreachDaemon
extends RefCounted
## Программа взлома — цепочка кодов, которую нужно собрать в буфере подряд (порт Daemon из :rules). Вес в буфере = sequence.size().
## Что демон делает при совпадении (эффект), движок не знает: он только считает совпадения; эффект применяет тот, кто вызвал взлом.

var id := ""
var display_name := ""
var sequence: Array = []      # коды (строки) подряд
var tier := 1                 # 1/2/3 = BASE/HARD/NIGHTMARE
var effect := "EXTRACT_SHARD"  # имя как в DaemonEffect приложения


static func make(id_: String, sequence_: Array, effect_: String = "EXTRACT_SHARD", tier_: int = 1, name_: String = "") -> BreachDaemon:
	var d := BreachDaemon.new()
	d.id = id_
	d.sequence = sequence_.duplicate()
	d.effect = effect_
	d.tier = tier_
	d.display_name = name_ if name_ != "" else id_
	return d


## Из словаря: {id, sequence | cells, effect?, tier?, name?}. Демон в документе item Моста держит цепочку в `cells`.
## null — нет id или цепочки (пустая цепочка допустима: такой демон не совпадает никогда — крайний случай golden).
static func from_dict(d: Dictionary) -> BreachDaemon:
	var seq: Variant = d.get("sequence", d.get("cells"))
	if str(d.get("id", "")) == "" or not (seq is Array):
		return null
	var codes: Array = []
	for c in seq:
		codes.append(str(c))
	return make(str(d["id"]), codes, str(d.get("effect", "EXTRACT_SHARD")), int(d.get("tier", 1)), str(d.get("name", "")))


func length() -> int:
	return sequence.size()
