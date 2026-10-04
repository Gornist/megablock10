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
