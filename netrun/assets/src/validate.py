#!/usr/bin/env python3
"""Проверка ассетов «Сети» и сборка MANIFEST.md. Чистый Python, без Blender и без токенов.

    python3 netrun/assets/src/validate.py            — проверить все ассеты из reports/, код возврата 1 при ошибках
    python3 netrun/assets/src/validate.py --manifest — ещё и записать models/MANIFEST.md

Числа берутся заново из самого .glb (`glbinfo`), отчёт сборки нужен только ради бюджетов и origin.
Проверяем то, что можно проверить без устройства: треугольники, точки, слои прозрачности, материалы-роли, атрибуты,
масштаб, origin, трансформации узлов. Частота кадров на Pico 4 здесь НЕ проверяется.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import glbinfo  # noqa: E402

ROLES = {"glow_edge", "shell_soft", "points", "streaks", "solid_dark"}
MAX_LAYERS = 3  # вложенных прозрачных оболочек на один ассет (STYLE.md)
# Бюджет вариантов пола env/floor_v<N>_16 (карточка 2026-10-05): v1 «пыль» — до 900 штрихов (повышенный), остальные до 600; слоёв ≤ 3 (MAX_LAYERS). Бюджет узла ≈ 220 тыс. треугольников, на Pico не мерили.
FLOOR_V_LIMITS = {"tris": 600, "points": 900, "streaks": 600, "streaks_v1": 900}
MAX_DRAWS = 8  # примитивов (≈ вызовов отрисовки) на ассет; предварительно, уточнить замером
# Узлы-метки предметов узла: контракт с клиентом (ARCHITECTURE.md, «Предметы узла»), без них клиент не сможет включить состояние, тир, экран.
REQUIRED_NODES = {
    "vault": ("State_closed", "State_open", "State_empty", "Tier_1", "Tier_2", "Tier_3", "ShardSlot"),
    "shard": ("Tier_1", "Tier_2", "Tier_3"),
    "shard_encrypted": ("Tier_1", "Tier_2", "Tier_3"),
    "hack_panel": ("Screen", "ScreenAnchor"),
}


def check(rep):
    path = os.path.join(ROOT, rep["file"])
    if not os.path.exists(path):
        return ["нет файла " + rep["file"]], {}
    info = glbinfo.parse(path)
    s = glbinfo.summary(info)
    bad = []
    if s["tris"] > rep["budget_tris"]:
        bad.append(f"треугольников {s['tris']} > {rep['budget_tris']}")
    if s["points"] > rep.get("budget_points", 0):
        bad.append(f"точек {s['points']} > {rep.get('budget_points', 0)}")
    if s["streaks"] > rep.get("budget_streaks", 0):
        bad.append(f"штрихов {s['streaks']} > {rep.get('budget_streaks', 0)}")
    if s["layers"] > MAX_LAYERS:
        bad.append(f"слоёв прозрачности {s['layers']} > {MAX_LAYERS}")
    mats = set(info["materials"])
    if not mats <= ROLES:
        bad.append(f"неизвестные материалы {sorted(mats - ROLES)}")
    if "glow_edge" in mats:
        bad.append("glow_edge: сплошные рейки запрещены (STYLE.md), грань — плотность частиц")
    draws = len(info["prims"])
    max_draws = rep.get("budget_draws") or MAX_DRAWS  # составные предметы (хранилище: три состояния в одном файле) заявляют свой предел
    if draws > max_draws:
        bad.append(f"примитивов {draws} > {max_draws} (каждый — вызов отрисовки)")
    # ЭКСПЕРИМЕНТ «варианты пола» (env/floor_v<N>_<размер>): общий бюджет из карточки поверх заявленного в отчёте; для _8 — по площади (×0,25)
    if rep["name"].startswith("floor_v"):
        k = (int(rep["name"].rsplit("_", 1)[1]) / 16.0) ** 2
        lim_s = FLOOR_V_LIMITS["streaks_v1" if rep["name"].startswith("floor_v1_") else "streaks"] * k
        for what, have, lim in (("треугольников", s["tris"], FLOOR_V_LIMITS["tris"] * k), ("точек", s["points"], FLOOR_V_LIMITS["points"] * k), ("штрихов", s["streaks"], lim_s)):
            if have > lim:
                bad.append(f"вариант пола: {what} {have} > {lim:g} (бюджет карточки)")
    missing = [n for n in REQUIRED_NODES.get(rep["name"], ()) if n not in info.get("node_names", [])]
    if missing:
        bad.append(f"нет узлов-меток контракта: {missing}")
    if info["moved_nodes"]:
        bad.append(f"узлов с трансформацией: {info['moved_nodes']} (применить трансформации)")
    for p in info["prims"]:
        # вуаль плит (`*_skirt`): роль shell_soft (шейдер skirt.gdshader подставляет Godot по имени меша), по одному квадрату на грань
        if str(p["mesh"]).endswith("_skirt"):
            if p["material"] != "shell_soft":
                bad.append(f"{p['mesh']}: вуаль должна быть ролью shell_soft, а не {p['material']}")
            if p["verts"] != p["tris"] * 2:
                bad.append(f"{p['mesh']}: вуаль — по одному квадрату (2 треугольника, 4 вершины) на грань, а тут {p['tris']} треуг. и {p['verts']} вершин")
        # верх стеклянного пола (`*_glass`, эксперимент env/floor_glass_<N>): роль shell_soft (шейдер glass.gdshader по имени меша), один квад (2 треугольника), один слой
        if str(p["mesh"]).endswith("_glass"):
            if p["material"] != "shell_soft":
                bad.append(f"{p['mesh']}: верх стеклянного пола должен быть ролью shell_soft, а не {p['material']}")
            if p["tris"] != 2 or p["verts"] != 4:
                bad.append(f"{p['mesh']}: верх стеклянного пола — один квад (2 треугольника, 4 вершины), а тут {p['tris']} треуг. и {p['verts']} вершин")
            if "TEXCOORD_0" not in p["attrs"]:
                bad.append(f"{p['mesh']}: нет UV (шейдеру нужно расстояние до кромки)")
        # дымка горизонта (`*_mist`): роль shell_soft (шейдер haze.gdshader по имени меша), один слой, не больше 200 треугольников на всю ленту (overdraw на Pico 4 не мерили)
        if str(p["mesh"]).endswith("_mist"):
            if p["material"] != "shell_soft":
                bad.append(f"{p['mesh']}: дымка должна быть ролью shell_soft, а не {p['material']}")
            if p["tris"] > 200:
                bad.append(f"{p['mesh']}: дымка {p['tris']} треугольников > 200")
        need = {"COLOR_0", "NORMAL"} | ({"TEXCOORD_1"} if p["material"] in ("points", "streaks") else set())
        if not need <= set(p["attrs"]):
            bad.append(f"{p['mesh']}: нет атрибутов {sorted(need - set(p['attrs']))}")
    lo, hi, size = info["bbox_min"], info["bbox_max"], info["size"]
    horizon = rep["origin"] == "horizon"  # кольцо горизонта: габарит ~140 м, это его суть
    edge = rep["origin"] == "edge"  # кромка комнаты (room_edge_<N>): габарит до 20 м (квадрат 16 м + дымка 1,8 м наружу)
    slab = rep["origin"] == "slab"  # пол комнаты одной плитой (env/floor_slab_<N>, эксперимент): габарит до 20 м, сторона плиты = N
    floorv = rep["origin"] == "floorv"  # варианты пола env/floor_v<N>_<размер>: габарит до 20 м
    moat = rep["origin"] == "moat"  # ров вокруг плиты-пола (env/room_moat_<N>): плоское кольцо, габарит до 24 м (16 м + щель 0,35 м + полоса 3 м с каждой стороны)
    if not 0.01 <= max(size) <= (150 if horizon else 24.0 if moat else 20.0 if edge or slab or floorv else 12):
        bad.append(f"странный размер {size} (1 единица = 1 м)")
    # «moat» — центр квадрата на уровне пола: плоское кольцо чуть ниже пола (−0,03…0), по xz симметрично и не шире 12 м от центра
    if moat:
        if lo[1] < -0.03 or hi[1] > 0.0:
            bad.append(f"origin «moat»: по высоте вне −0,03…0 м: min.y={lo[1]:.3f}, max.y={hi[1]:.3f}")
        if max(abs(lo[0]), abs(lo[2]), abs(hi[0]), abs(hi[2])) > 12.0 or abs(lo[0] + hi[0]) > 0.05 or abs(lo[2] + hi[2]) > 0.05:
            bad.append(f"origin «moat»: габарит шире 12 м от центра или несимметричен: min={[round(v, 2) for v in lo]}, max={[round(v, 2) for v in hi]}")
    # «edge» — центр квадрата на уровне пола: по высоте от −3 м (подвесные штрихи) до +0,55 м (низкая дымка до колена), по xz симметрично и не шире 10 м от центра
    if edge:
        if lo[1] < -3.0 or hi[1] > 0.55:
            bad.append(f"origin «edge»: по высоте вне −3…+0,55 м: min.y={lo[1]:.2f}, max.y={hi[1]:.2f}")
        if max(abs(lo[0]), abs(lo[2]), abs(hi[0]), abs(hi[2])) > 10.0 or abs(lo[0] + hi[0]) > 0.3 or abs(lo[2] + hi[2]) > 0.3:
            bad.append(f"origin «edge»: габарит шире 10 м от центра или несимметричен: min={[round(v, 2) for v in lo]}, max={[round(v, 2) for v in hi]}")
    # «slab» — центр плиты на уровне пола: верх плиты и точки швов не выше 4 см над полом (выступов нет), штрихи вниз не глубже 1,2 м, по xz симметрично
    if slab:
        if hi[1] > 0.04 or lo[1] < -1.2:
            bad.append(f"origin «slab»: по высоте вне −1,2…+0,04 м: min.y={lo[1]:.2f}, max.y={hi[1]:.3f}")
        if max(abs(lo[0]), abs(lo[2]), abs(hi[0]), abs(hi[2])) > 10.0 or abs(lo[0] + hi[0]) > 0.1 or abs(lo[2] + hi[2]) > 0.1:
            bad.append(f"origin «slab»: габарит шире 10 м от центра или несимметричен: min={[round(v, 2) for v in lo]}, max={[round(v, 2) for v in hi]}")
    # «floorv» — вариант пола (env/floor_v<N>_<размер>): центр квадрата на уровне пола; плиты не выше пола, штрихи «пыли» до 0,35 м над ним (не коллизия), подвесные — не глубже 1,2 м
    if rep["origin"] == "floorv":
        if hi[1] > 0.4 or lo[1] < -1.2:
            bad.append(f"origin «floorv»: по высоте вне −1,2…+0,4 м: min.y={lo[1]:.2f}, max.y={hi[1]:.3f}")
        if rep["name"].rsplit("_", 1)[0] != "floor_v1" and hi[1] > 0.04:
            bad.append(f"origin «floorv»: выше пола max.y={hi[1]:.3f} (допуск 0,04; выше — только штрихи «пыли» floor_v1)")
        if max(abs(lo[0]), abs(lo[2]), abs(hi[0]), abs(hi[2])) > 10.0 or abs(lo[0] + hi[0]) > 0.1 or abs(lo[2] + hi[2]) > 0.1:
            bad.append(f"origin «floorv»: габарит шире 10 м от центра или несимметричен: min={[round(v, 2) for v in lo]}, max={[round(v, 2) for v in hi]}")
    # «horizon» — кольцо вокруг центра узла: радиус не ближе 35 м и не дальше 75 м, по высоте −3…+9 м (у размеров штрихов запас на ширину)
    if horizon:
        if max(abs(lo[0]), abs(lo[2]), abs(hi[0]), abs(hi[2])) > 75 or lo[1] < -3.1 or hi[1] > 9.0:
            bad.append(f"origin «horizon»: габарит вне 75 м по xz или −3…+9 м по высоте: min={[round(v, 1) for v in lo]}, max={[round(v, 1) for v in hi]}")
        if min(hi[0], hi[2], -lo[0], -lo[2]) < 30:
            bad.append("origin «horizon»: кольцо не охватывает центр (ближе 30 м с одной из сторон)")
    mid = [(lo[i] + hi[i]) / 2 for i in range(3)]
    if rep["origin"] == "floor" and (abs(lo[1]) > 0.01 or abs(mid[0]) > 0.05 or abs(mid[2]) > 0.05):
        bad.append(f"origin не на полу в центре: min.y={lo[1]:.3f}, центр xz=({mid[0]:.3f},{mid[2]:.3f})")
    tol = 0.05 + 0.02 * max(size)  # облака точек не бывают идеально центрированы: допуск растёт с размером
    if rep["origin"] == "center" and any(abs(m) > tol for m in mid):
        bad.append(f"origin не в центре: центр={[round(m, 3) for m in mid]}, допуск {tol:.3f}")
    # «surface» — поверхность пола: геометрия может уходить вниз (штрихи под тайлами), но не глубже 1 м; центр по XZ как у модуля
    # дальние пласты (far_*) глубже: плиты-«ямы» до −2,6 м и штрихи до −3 м (решение владельца); в комнате глубина по-прежнему 1 м
    depth = 3.0 if rep["name"].startswith("far_") else 1.0
    if rep["origin"] == "surface":
        if lo[1] < -depth or hi[1] < -0.01:
            bad.append(f"origin «surface»: min.y={lo[1]:.2f} (глубже {depth:g} м) или всё под полом, max.y={hi[1]:.2f}")
        if hi[1] > 0.04:  # 4 см — размер точки на полу; выше — выступ над поверхностью, это коллизии
            bad.append(f"origin «surface»: геометрия выше поверхности пола, max.y={hi[1]:.3f} (допуск 0.04, только точки)")
        if abs(mid[0]) > 0.05 or abs(mid[2]) > 0.05:
            bad.append(f"origin не в центре плитки: центр xz=({mid[0]:.3f},{mid[2]:.3f})")
    # «ceiling» — потолок, зеркало «surface»: origin на плоскости потолка, геометрия уходит вверх (до 1 м) и не выступает вниз в комнату
    if rep["origin"] == "ceiling":
        if hi[1] > depth or lo[1] > 0.01:
            bad.append(f"origin «ceiling»: max.y={hi[1]:.2f} (выше {depth:g} м) или всё над плоскостью, min.y={lo[1]:.3f}")
        if lo[1] < -0.04:  # 4 см — размер точки; ниже — выступ в комнату, это коллизии
            bad.append(f"origin «ceiling»: геометрия ниже плоскости потолка, min.y={lo[1]:.3f} (допуск −0.04, только точки)")
        if abs(mid[0]) > 0.05 or abs(mid[2]) > 0.05:
            bad.append(f"origin не в центре плитки: центр xz=({mid[0]:.3f},{mid[2]:.3f})")
    # «feet» — существа: ноги/якорь в (0,0) внутри габарита по XZ и на полу; центр габарита не требуем (существо асимметрично)
    if rep["origin"] == "feet" and (abs(lo[1]) > 0.01 or not (lo[0] - 0.05 <= 0 <= hi[0] + 0.05 and lo[2] - 0.05 <= 0 <= hi[2] + 0.05)):
        bad.append(f"origin не у ног: min.y={lo[1]:.3f}, якорь (0,0) вне габарита xz")
    return bad, {**s, "draws": draws, "size": size, "materials": sorted(mats), "animations": info["animations"]}


def main():
    global ROOT
    if "--root" in sys.argv:  # проверка на чужом каталоге (тесты): корень с models/ и reports/
        ROOT = os.path.abspath(sys.argv[sys.argv.index("--root") + 1])
    reps = []
    rdir = os.path.join(ROOT, "reports")
    for f in sorted(os.listdir(rdir)) if os.path.isdir(rdir) else []:
        if f.endswith(".json") and (not f.startswith("_") or "--all" in sys.argv):
            reps.append(json.load(open(os.path.join(rdir, f))))
    fails, rows = 0, []
    for rep in reps:
        bad, m = check(rep)
        fails += bool(bad)
        rows.append((rep, m, bad))
        print(("FAIL " if bad else "ok   ") + rep["name"] + (" — " + "; ".join(bad) if bad else ""))
    print(f"\nассетов: {len(rows)}, с ошибками: {fails}. Частота кадров на Pico 4 не проверялась.")
    if "--manifest" in sys.argv:
        lines = [
            "# Манифест ассетов «Сети»", "",
            "Собирается `src/validate.py --manifest`, руками не править. Числа взяты из самих `.glb`.",
            "Частота кадров на Pico 4 **не проверена** (нет устройства).", "",
            "| Файл | Треуг. / бюджет | Точек / бюджет | Штрихов / бюджет | Слоёв | Вызовов | Размер, м (x, y, z) | Материалы | Анимации | Origin | Статус |",
            "|---|---|---|---|---|---|---|---|---|---|---|",
        ]
        for rep, m, bad in rows:
            if not m:
                continue
            lines.append(
                f"| `{rep['file']}` | {m['tris']} / {rep['budget_tris']} | {m['points']} / {rep.get('budget_points', 0)} | {m['streaks']} / {rep.get('budget_streaks', 0)} | "
                f"{m['layers']} | {m['draws']} | {' × '.join(str(x) for x in m['size'])} | {', '.join(m['materials'])} | "
                f"{', '.join(m['animations']) or '—'} | {rep['origin']} | {'ошибки: ' + '; '.join(bad) if bad else 'ок'} |"
            )
        out = os.path.join(ROOT, "models", "MANIFEST.md")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        open(out, "w").write("\n".join(lines) + "\n")
        print("записан", out)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
