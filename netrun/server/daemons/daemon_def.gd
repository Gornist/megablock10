class_name DaemonDef
extends RefCounted
## Описание демона — только данные (JSON в data/daemons/). Поведение — в DaemonEffects по имени эффекта.

var id: String
var effect: String  # имя как в DaemonEffect приложения: GHOST, JITTER, EXTRACT_SHARD …
var tier: int = 1
var cooldown_sec: float = 0.0
var params: Dictionary = {}


## Из словаря; null, если не хватает id/effect.
static func from_dict(d: Dictionary) -> DaemonDef:
	if str(d.get("id", "")) == "" or str(d.get("effect", "")) == "":
		return null
	var def := DaemonDef.new()
	def.id = str(d["id"])
	def.effect = str(d["effect"])
	def.tier = int(d.get("tier", 1))
	def.cooldown_sec = float(d.get("cooldown_sec", 0.0))
	def.params = d.get("params", {})
	return def
