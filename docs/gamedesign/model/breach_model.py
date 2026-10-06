"""Модель сложности взлома (docs/gamedesign/breach.md, раздел 4). Запуск: python3 docs/gamedesign/model/breach_model.py [--trials N]

Повторяет генератор rules/…/BreachEngine.kt (generateGrid: путь-решение по правилу строка/столбец, остальное случайно, ловушки вне пути)
и меряет долю «добыча взята» у трёх моделей игрока на одних и тех же сетках:
  жадный    — смотрит на 1 ход: жмёт клетку со следующим нужным кодом, иначе случайную; мёртвые клетки обходит, порченые не замечает;
  думающий  — перебирает 3 хода вперёд, порченые не замечает;
  решатель  — путь заложен генератором, решает всегда (столбец не печатается: 100 % по построению).
Взлом 2.0: замок хранилища собирается первым; добыча (первый демон деки — Извлечение) засчитывается, только если её цепочка
кончилась после замка. Порченые коды 2.0 — «приманки»: ставятся на клетки с нужным кодом на линиях пути, а не случайно.
Это модель, а не эталон: эталон — Kotlin-тест «щуп сложности» (docs/gamedesign/breach.md, раздел 5)."""
import random
import sys

ALPH = ["1C", "55", "BD", "E9", "7A", "FF"]


def cands(frm, k, n, visited):
    """Правило BreachRules.nextLinkDimension/candidatesFor: после k выбранных клеток следующая — в столбце (k нечётно) или строке."""
    r, c = frm
    cells = [(i, c) for i in range(n)] if (k - 1) % 2 == 0 else [(r, j) for j in range(n)]
    return [x for x in cells if x != frm and x not in visited]


def contains(buf, s):
    return any(buf[i:i + len(s)] == s for i in range(len(buf) - len(s) + 1))


def ends(buf, s):
    return [i + len(s) for i in range(len(buf) - len(s) + 1) if buf[i:i + len(s)] == s]


def loot_ok(buf, lock, extract):
    e = ends(buf, extract)
    if not e:
        return False
    if not lock:
        return True
    l = ends(buf, lock)
    return bool(l) and l[0] <= e[-1] - len(extract)


def gen(n, seqs, ndead, ncorr, rnd, decoys):
    codes = [x for s in seqs for x in s]
    while True:
        path = [(0, rnd.randrange(n))]
        vis = set(path)
        while len(path) < len(codes):
            cs = cands(path[-1], len(path), n, vis)
            if not cs:
                break
            nx = rnd.choice(cs)
            path.append(nx)
            vis.add(nx)
        if len(path) == len(codes):
            break
    g = [[None] * n for _ in range(n)]
    for i, (r, c) in enumerate(path):
        g[r][c] = codes[i]
    for r in range(n):
        for c in range(n):
            if g[r][c] is None:
                g[r][c] = rnd.choice(ALPH)
    free = [(r, c) for r in range(n) for c in range(n) if (r, c) not in vis]
    rnd.shuffle(free)
    dead = free[:ndead]
    for (r, c) in dead:
        g[r][c] = "××"
    rest = free[ndead:]
    if decoys:
        needed = set(codes)
        rows = {r for r, _ in path}
        cols = {c for _, c in path}
        rest.sort(key=lambda x: (g[x[0]][x[1]] not in needed, not (x[0] in rows or x[1] in cols)))
    return g, set(dead), set(rest[:ncorr])


def legal(path, vis, n, dead):
    cs = [(0, j) for j in range(n)] if not path else cands(path[-1], len(path), n, vis)
    return [x for x in cs if x not in dead]


def greedy(g, dead, corr, seqs, buf_len, n, rnd):
    path, vis, buf = [], set(), []
    while len(buf) < buf_len:
        cs = legal(path, vis, n, dead)
        todo = [s for s in seqs if not contains(buf, s)]
        if not cs or not todo:
            break
        s, k = todo[0], 0
        for L in range(min(len(s) - 1, len(buf)), 0, -1):
            if buf[-L:] == s[:L]:
                k = L
                break
        good = [x for x in cs if g[x[0]][x[1]] == s[k]] or ([x for x in cs if g[x[0]][x[1]] == s[0]] if k else [])
        x = rnd.choice(good) if good else rnd.choice(cs)
        path.append(x)
        vis.add(x)
        buf.append("  " if x in corr else g[x[0]][x[1]])
    return buf


def thinker(g, dead, corr, seqs, buf_len, n, rnd, lock, extract, depth=3):
    def score(b):
        todo = [s for s in seqs if not contains(b, s)]
        prog = 0
        if todo:
            s = todo[0]
            for L in range(min(len(s) - 1, len(b)), 0, -1):
                if b[-L:] == s[:L]:
                    prog = L
                    break
        return (loot_ok(b, lock, extract), len(seqs) - len(todo), prog)

    def best(p, v, b, d):
        sc = score(b)
        if d == 0 or len(b) >= buf_len or sc[0]:
            return sc
        return max([sc] + [best(p + [x], v | {x}, b + [g[x[0]][x[1]]], d - 1) for x in legal(p, v, n, dead)])

    path, vis, buf = [], set(), []
    while len(buf) < buf_len and not (loot_ok(buf, lock, extract) and all(contains(buf, s) for s in seqs)):
        ms = legal(path, vis, n, dead)
        if not ms:
            break
        x = max(ms, key=lambda m: (best(path + [m], vis | {m}, buf + [g[m[0]][m[1]]], depth - 1), rnd.random()))
        path.append(x)
        vis.add(x)
        buf.append("  " if x in corr else g[x[0]][x[1]])
    return buf


def run(label, n, lens, ram, dead_rng, corr_rng, lock_len, slack, decoys, trials, seed=11):
    rnd = random.Random(seed)
    hit = {"g": 0, "t": 0}
    buf_len = 0
    for _ in range(trials):
        demons = [[rnd.choice(ALPH) for _ in range(L)] for L in lens]
        lock = [rnd.choice(ALPH) for _ in range(lock_len)]
        seqs = ([lock] if lock else []) + demons
        buf_len = min(ram, sum(len(s) for s in seqs) + slack)
        assert buf_len >= sum(len(s) for s in seqs), f"{label}: дека не влезает в буфер"
        g, dead, corr = gen(n, seqs, rnd.randint(*dead_rng), rnd.randint(*corr_rng), rnd, decoys)
        hit["g"] += loot_ok(greedy(g, dead, corr, seqs, buf_len, n, rnd), lock, demons[0])
        hit["t"] += loot_ok(thinker(g, dead, corr, seqs, buf_len, n, rnd, lock, demons[0]), lock, demons[0])
    print(f"| {label} | {buf_len} | {100 * hit['g'] // trials} % | {100 * hit['t'] // trials} % |")


if __name__ == "__main__":
    trials = int(sys.argv[sys.argv.index("--trials") + 1]) if "--trials" in sys.argv else 400
    print("| Сейчас | буфер | жадный | думающий |\n|---|---|---|---|")
    run("BASE 5×5, демон 2, RAM 6", 5, [2], 6, (0, 0), (0, 0), 0, 99, False, trials)
    run("HARD 6×6, демоны 3+3, RAM 8", 6, [3, 3], 8, (2, 3), (0, 0), 0, 99, False, trials)
    run("NIGHTMARE 7×7, демоны 3+4, RAM 10", 7, [3, 4], 10, (5, 6), (2, 3), 0, 99, False, trials)
    print("\n| Взлом 2.0 (замок 1/2/3, запас 2/1/0, приманки 0/1–2/3–4) | буфер | жадный | думающий |\n|---|---|---|---|")
    run("BASE 5×5, демон 2, RAM 6", 5, [2], 6, (0, 0), (0, 0), 1, 2, False, trials)
    run("BASE 5×5, демон 3, RAM 6", 5, [3], 6, (0, 0), (0, 0), 1, 2, False, trials)
    run("HARD 6×6, демон 3, RAM 6", 6, [3], 6, (2, 3), (1, 2), 2, 1, True, trials)
    run("HARD 6×6, демоны 3+3, RAM 9", 6, [3, 3], 9, (2, 3), (1, 2), 2, 1, True, trials)
    run("NIGHTMARE 7×7, демон 4, RAM 8", 7, [4], 8, (5, 6), (3, 4), 3, 0, True, trials)
    run("NIGHTMARE 7×7, демоны 3+4, RAM 10", 7, [3, 4], 10, (5, 6), (3, 4), 3, 0, True, trials)
    print("\n| Рычаг: замок длиннее | буфер | жадный | думающий |\n|---|---|---|---|")
    run("HARD замок 3, демон 3, RAM 7", 6, [3], 7, (2, 3), (1, 2), 3, 1, True, trials)
    run("NIGHTMARE замок 4, демон 4, RAM 8", 7, [4], 8, (5, 6), (3, 4), 4, 0, True, trials)
