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
MAX_DRAWS = 8   # примитивов (≈ вызовов отрисовки) на ассет; предварительно, уточнить замером


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
    if draws > MAX_DRAWS:
        bad.append(f"примитивов {draws} > {MAX_DRAWS} (каждый — вызов отрисовки)")
    if info["moved_nodes"]:
        bad.append(f"узлов с трансформацией: {info['moved_nodes']} (применить трансформации)")
    for p in info["prims"]:
        # вуаль плит (`*_skirt`): роль shell_soft (шейдер skirt.gdshader подставляет Godot по имени меша), по одному квадрату на грань
        if str(p["mesh"]).endswith("_skirt"):
            if p["material"] != "shell_soft":
                bad.append(f"{p['mesh']}: вуаль должна быть ролью shell_soft, а не {p['material']}")
            if p["verts"] != p["tris"] * 2:
                bad.append(f"{p['mesh']}: вуаль — по одному квадрату (2 треугольника, 4 вершины) на грань, а тут {p['tris']} треуг. и {p['verts']} вершин")
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
    if not 0.01 <= max(size) <= (150 if horizon else 12):
        bad.append(f"странный размер {size} (1 единица = 1 м)")
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
