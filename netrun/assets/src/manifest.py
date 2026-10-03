#!/usr/bin/env python3
"""Собирает models/MANIFEST.md из готовых .glb (число треугольников, материалы, анимации, габариты — считаются из файлов)
и описаний в src/meta/*.py (назначение, origin). Чистый Python.

    python3 netrun/assets/src/manifest.py

Файл генерируемый: правьте meta/*.py и сами скрипты, не MANIFEST.md. Новая группа (ice, avatar, deck) — новый модуль meta/<группа>.py.
"""
import importlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_budget as cb  # noqa: E402
import palette  # noqa: E402

MODELS = os.path.join(os.path.dirname(HERE), "models")
TIER_SUFFIXES = [spec["suffix"] for spec in palette.TIERS.values() if spec["suffix"]]
GROUP_TITLES = {
    "env": "Окружение (env)",
    "props": "Предметы (props)",
    "ice": "Существа: ICE (ice)",
    "avatar": "Аватар (avatar)",
    "deck": "Кибердека (deck)",
}

HEADER = """# Каталог 3D-ассетов «Сети»

Файл создаёт `netrun/assets/src/manifest.py` из готовых `.glb` — числа здесь не правятся руками. ТЗ: `docs/netrun-assets-brief.md`.
Статус: сделаны группы **env** и **props**; ice, avatar, deck и сцена `preview.tscn` — следующая часть задачи.

## Как пересобрать

Блендер — только на devbox (на Mac 8 ГБ не запускать):

```sh
scp -r netrun/assets devbox:/tmp/a1/ && ssh devbox 'bash /tmp/a1/assets/src/build_all.sh'   # модели, превью, проверка, этот файл
scp -r devbox:/tmp/a1/assets/models devbox:/tmp/a1/assets/previews netrun/assets/             # забрать результат
python3 netrun/assets/src/check_budget.py                                                    # бюджет по готовым .glb (без Blender)
```

Скрипты: `palette.py` (палитра), `bl_common.py` (геометрия, материалы, экспорт), `build_env.py`, `build_props.py`, `preview.py`
(превью Workbench), `check_budget.py`, `patch_imports.py` (облегчённые настройки импорта Godot). Превью — `netrun/assets/previews/`
(серый столбик — 1,2 м, высота глаз сидящего; планка на полу — 1 м; тела на превью осветлены, неон без свечения),
`previews/assembly.png` — собранный уголок узла для проверки стыков сетки.

## Соглашения

- **Единицы и оси.** glTF 2.0 (`.glb`), Y вверх, 1 ед. = 1 м, масштаб 1, трансформации запечены. В Godot корень сцены — `Node3D` с именем
  файла, под ним меш `MeshInstance3D` с именем `Mesh` (у `lockdown_gate` два: `Frame` и `Bars_Closed`) и метки `Node3D`
  (`ShardSlot`, `SeatAnchor`, `EyeAnchor`). Анимаций в env/props нет.
- **Лицо.** Лицо предмета (дверца, линза, арка, внутренняя сторона стены) смотрит в **+Z**: так его видит игрок, смотрящий вдоль -Z
  (вперёд в Godot, см. `NodeLayout`). Существа и сидящий (кресло, ICE, аватар) смотрят вперёд, то есть в **-Z**.
- **Сетка.** Модули окружения — ячейка 2x2 м, origin на полу в центре ячейки. Стена стоит на крае ячейки z=-1 и входит внутрь на
  0,2 м; на другие края — поворотом вокруг Y на 90/180/270. Комната узла 16x16 м из `NodeLayout` — 8x8 ячеек, центры ячеек в нечётных
  координатах (x = -7…7, z = -13…1).
- **Тиры.** BASE, HARD, NIGHTMARE — те же меши, разные материалы: `<имя>.glb` (BASE), `<имя>_hard.glb`, `<имя>_nightmare.glb`.
  Тир меняет цвет тела и неон (бирюзовый, оранжевый, красный). Число треугольников у трёх файлов одинаковое (проверяет `check_budget.py`).
- **Материалы.** Один тёмный плоский «корпус» (`env_body_<ТИР>`, `prop_body`) и один неон (`env_neon_<ТИР>`, `prop_neon_*`):
  `base_color` и `emission` одного цвета, сила 1,6 у окружения и 2,2 у предметов (`KHR_materials_emissive_strength`, Godot читает как
  `emission_energy_multiplier`). Без текстур, прозрачности, теней, вершинных цветов; обратные грани отсекаются.
- **Палитра** (из `docs/ux/ui-style-guide.md`, смысл цвета тот же): `acc #5EF6FF` — интерактивное, тир BASE, портал, кресло;
  `warn #FF9F43` — «ждёт действия», тир HARD, закрытое хранилище, зашифрованный шард; `bad #FF5A50` — опасность, тир NIGHTMARE,
  датчик, запертые ворота; `money #F5D547` — добыча (шард); `ok #43F08F` — открытое хранилище; `chrome #C65A52` — мёртвая дека.
  Тела: BASE `#15272B`, HARD `#2B1F14`, NIGHTMARE `#2E1215`, предметы `#2A2D31`. Лайм гайдлайна (экраны взлома) в мире не используется.
- **Импорт Godot.** `.glb.import` лежат в git (стабильные uid, как у остальных ассетов репозитория). `patch_imports.py` выключает тангенты,
  LOD и теневые меши — для очков они только съедают память. После правки .glb: `godot --headless --path netrun --import`.
"""


def load_meta():
    meta = {}
    mdir = os.path.join(HERE, "meta")
    for fn in sorted(os.listdir(mdir)):
        if fn.endswith(".py") and not fn.startswith("_"):
            meta.update(importlib.import_module("meta." + fn[:-3]).META)
    return meta


def fmt_mats(info, tiered):
    names = info["materials"]
    if tiered:
        names = [re.sub(r"_(BASE|HARD|NIGHTMARE)$", "_<ТИР>", n) for n in names]
    return ", ".join("`%s`" % n for n in names)


def fmt_size(info):
    return " x ".join(("%.2f" % v).replace(".", ",") for v in info["size"])


def main():
    infos = cb.scan(MODELS)
    by_key = {"%s/%s" % (i["group"], i["name"]): i for i in infos}
    meta = load_meta()
    out = [HEADER]
    for group in [g for g in GROUP_TITLES if any(i["group"] == g for i in infos)]:
        out.append("\n## %s\n" % GROUP_TITLES[group])
        out.append("| Файл | Назначение | Треуг. / бюджет | Материалы | Анимации | Origin | Размеры X x Y x Z, м |")
        out.append("|---|---|---|---|---|---|---|")
        for i in [x for x in infos if x["group"] == group]:
            stem = i["name"]
            if any(stem.endswith(sfx) for sfx in TIER_SUFFIXES):
                continue  # тиры сворачиваем в строку BASE
            key = "%s/%s" % (group, stem)
            m = meta.get(key, {})
            tiered = bool(m.get("tiers"))
            if tiered:
                missing = [s for s in TIER_SUFFIXES if "%s/%s%s" % (group, stem, s) not in by_key]
                if missing:
                    raise SystemExit("%s: нет файлов тиров %s" % (key, missing))
                files = "`%s/%s.glb` (+ `_hard`, `_nightmare`)" % (group, stem)
            else:
                files = "`%s/%s.glb`" % (group, stem)
            limit, from_brief = cb.budget_for(group, stem)
            budget = "%d / %d%s" % (i["tris"], limit, "" if from_brief else " *")
            anim = ", ".join("`%s`" % a for a in i["animations"]) or "—"
            out.append("| %s | %s | %s | %s | %s | %s | %s |" % (
                files, m.get("purpose", "—"), budget, fmt_mats(i, tiered), anim, m.get("origin", "—"), fmt_size(i)))
        if any(not cb.budget_for(group, i["name"])[1] for i in infos if i["group"] == group):
            out.append("\n\\* ТЗ числа не задаёт; принят потолок 2000 как для остальных предметов.")
    out.append("\nМетки (`Node3D`) и их положение: `ShardSlot` у хранилищ, `SeatAnchor` и `EyeAnchor` у кресла (см. таблицу props).")
    path = os.path.join(MODELS, "MANIFEST.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print("записан", os.path.relpath(path, os.path.dirname(MODELS)), "— ассетов:", len(infos))


if __name__ == "__main__":
    main()
