class_name AlarmLevels
extends RefCounted
## Уровни тревоги узла по шкале 0–100 (docs/gamedesign/ice.md §4): общие для сервера (GrayNode) и клиента (вид тревоги, строка деки).

## Пороги уровней 1…4: 25 насторожен, 50 тревога, 75 охота, 100 локдаун.
const AT := [25.0, 50.0, 75.0, 100.0]
const MAX_LEVEL := 4
const NAMES := ["спокойно", "насторожен", "тревога", "охота", "локдаун"]


## Уровень 0…4 по значению шкалы 0–100.
static func level_for(value: float) -> int:
	var level := 0
	for i in AT.size():
		if value >= float(AT[i]):
			level = i + 1
	return level


## Название уровня для строки деки/журнала.
static func name_of(level: int) -> String:
	return NAMES[clampi(level, 0, MAX_LEVEL)]
