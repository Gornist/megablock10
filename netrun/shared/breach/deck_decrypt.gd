class_name DeckDecrypt
extends RefCounted
## Правило расшифровки шарда на деке (К7; docs/netrun-deck-design.md §3.1): шифр-замок доступен, если среди рабочих демонов деки есть DECRYPT тира не ниже
## тира шарда (как `DecryptRules.bestDecrypter` в :rules — берётся ближайший по тиру). Одно правило для сервера (решает) и клиента (показывает кнопку).

const EFFECT := "DECRYPT"


## Лучший дешифратор среди daemons [{id, effect, tier, ...}] для шарда тира shard_tier; {} — нет.
static func best(daemons: Array, shard_tier: int) -> Dictionary:
	var pick := {}
	for d in daemons:
		if str(d.get("effect", "")) != EFFECT or int(d.get("tier", 0)) < shard_tier:
			continue
		if pick.is_empty() or int(d["tier"]) < int(pick["tier"]):
			pick = d
	return pick
