class_name DaemonDef
extends RefCounted
## Описание демона — только данные (JSON в data/daemons/). Поведение — в DaemonEffects по имени эффекта.

var id: String
var effect: String  # имя как в DaemonEffect приложения: GHOST, JITTER, EXTRACT_SHARD …
var tier: int = 1
var cooldown_sec: float = 0.0
var params: Dictionary = {}
var display_name: String = ""
var unsupported_reason: String = ""  # непусто — демон виден в деке, но в Сети не работает


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


## Из демона документа item Моста: {effect, tier, name, cells} (поле `daemon`, протокол Моста). Параметры эффекта по уровню —
## из tiers (содержимое effects/<ЭФФЕКТ>.json); null, если нет id/effect. Эффекта нет в Сети (tiers == null) — демон
## получает unsupported_reason: в деке он виден, применить его нельзя.
static func from_item(item_id: String, daemon: Dictionary, tiers: Variant, effect_known: bool) -> DaemonDef:
	var eff := str(daemon.get("effect", ""))
	if item_id == "" or eff == "":
		return null
	var def := DaemonDef.new()
	def.id = item_id
	def.effect = eff
	def.tier = clampi(int(daemon.get("tier", 1)), 1, 3)
	def.display_name = str(daemon.get("name", eff))
	if not effect_known or not (tiers is Dictionary):
		def.unsupported_reason = "эффект %s в Сети пока не работает" % eff
		return def
	var row: Variant = (tiers as Dictionary).get(str(def.tier))
	if not (row is Dictionary):
		def.unsupported_reason = "у эффекта %s нет параметров для уровня %d" % [eff, def.tier]
		return def
	def.cooldown_sec = float(row.get("cooldown_sec", 0.0))
	def.params = row.get("params", {})
	return def
