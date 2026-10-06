class_name BreachTestUtil
extends RefCounted
## Общее для тестов движка взлома: случайные наборы демонов и проигрывание пути.


## 1-3 демона с цепочками 2-5 кодов, суммарная длина не больше `budget`. Детерминирован от rng.
static func random_daemons(rng: RandomNumberGenerator, data: BreachData, budget: int) -> Array:
	var out: Array = []
	var left := budget
	var count := rng.randi_range(1, 3)
	for i in range(count):
		if left < 2:
			break
		var n := rng.randi_range(2, mini(5, left))
		var seq: Array = []
		for _k in range(n):
			seq.append(data.alphabet[rng.randi_range(0, data.alphabet.size() - 1)])
		out.append(BreachDaemon.make("d%d" % i, seq, "EXTRACT_SHARD", 1, "D%d" % i))
		left -= n
	return out


static func attempt_for(grid: BreachGrid, daemons: Array, buffer: int, data: BreachData) -> BreachAttempt:
	return BreachAttempt.make(grid, daemons, buffer, data)


static func total_length(daemons: Array) -> int:
	var t := 0
	for d in daemons:
		t += d.length()
	return t


## Событие `bk` в том виде, в каком его шлёт VaultBreach: публичная сетка без порченых кодов и без пути решения.
static func make_bk_event(tier: String = "HARD", seed_value: int = 77, ram: int = 6) -> Dictionary:
	var daemons := [BreachDaemon.make("d1", ["1C", "BD"], "EXTRACT_SHARD", 2, "Извлечение"), BreachDaemon.make("d2", ["55", "7A"], "GHOST", 1, "Призрак")]
	# Хранилище с замком требует RAM под «замок + цепочки» (breach.md 2.3): тесту, которому хватало 6, на NIGHTMARE (замок 3) добавляем.
	var need: int = int(BreachData.shared().tier_params(tier)["lock_length"]) + 4
	var run := BreachRun.for_storage(tier, daemons, maxi(ram, need), seed_value)
	var targets: Array = []
	for d in daemons:
		targets.append({"id": d.id, "name": d.display_name, "effect": d.effect, "cells": d.sequence})
	return {"kind": WorldMsg.EV_BK, "mode": "storage", "vault": "v1", "n": 1, "tier": tier, "grid": VaultBreach.public_grid(run.attempt.grid),
		"targets": targets, "buffer": run.attempt.buffer_size, "sec": run.timer_sec, "ice": "ICE: тест"}
