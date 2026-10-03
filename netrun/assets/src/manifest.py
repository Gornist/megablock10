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

FOOTNOTES = {"deck": "принят потолок 500 для жетона демона размером 3 см (у wrist_deck потолок 2000 задаёт ТЗ)"}

HEADER = """# Каталог 3D-ассетов «Сети»

Файл создаёт `netrun/assets/src/manifest.py` из готовых `.glb` — числа здесь не правятся руками. ТЗ: `docs/netrun-assets-brief.md`.
Статус: сделаны все группы набора — **env**, **props**, **ice**, **avatar**, **deck** — и собранная сцена `netrun/assets/preview.tscn`.

## Как пересобрать

Блендер — только на devbox (на Mac 8 ГБ не запускать):

```sh
scp -r netrun/assets devbox:/tmp/a1/ && ssh devbox 'bash /tmp/a1/assets/src/build_all.sh'   # модели, превью, проверка, сцена, этот файл
                                                                                             # (часть групп: ASSET_GROUPS="ice avatar deck" bash ...)
scp -r devbox:/tmp/a1/assets/models devbox:/tmp/a1/assets/previews netrun/assets/             # забрать результат
python3 netrun/assets/src/check_budget.py                                                    # бюджет по готовым .glb (без Blender)
# импорт Godot на devbox, в копии проекта: импорт -> patch_imports.py -> импорт; .glb.import забрать обратно в git
godot --headless --path netrun --import && python3 netrun/assets/src/patch_imports.py && godot --headless --path netrun --import
netrun/tools/gdunit.sh res://tests/assets_models_test.gd                                      # импорт, скелеты, клипы, метки, preview.tscn
```

Скрипты: `palette.py` (палитра), `bl_common.py` (геометрия, материалы, скелет `Rig`, экспорт), `build_env.py`, `build_props.py`,
`build_ice.py`, `build_avatar.py`, `build_deck.py`, `preview.py` (превью Workbench), `check_budget.py`, `patch_imports.py` (настройки
импорта Godot: облегчённые + зацикливание клипов), `make_preview_scene.py` (сцена `preview.tscn`). Превью — `netrun/assets/previews/`
(серый столбик — 1,2 м, высота глаз сидящего; планка на полу — 1 м; тела на превью осветлены, неон без свечения),
`previews/assembly.png` — собранный уголок узла для проверки стыков сетки, `previews/preview.png` — кадр из `preview.tscn` в Godot,
`previews/ice/silhouettes.png` — силуэты Soft ICE, Black ICE и аватара.
Скриншот сцены (на devbox, отдельным процессом Godot, редактор другого агента не трогаем):
`. ~/netrun-env.sh; DISPLAY=:0 XAUTHORITY=$(ls /run/user/1000/.mutter-Xwaylandauth.* | head -1) godot --path <копия netrun> res://assets/preview_shot.tscn`.

## Соглашения

- **Единицы и оси.** glTF 2.0 (`.glb`), Y вверх, 1 ед. = 1 м, масштаб 1, трансформации запечены. В Godot корень сцены — `Node3D` с именем
  файла, под ним меш `MeshInstance3D` с именем `Mesh` (у `lockdown_gate` два: `Frame` и `Bars_Closed`, у `wrist_deck` второй — `Screen`)
  и метки `Node3D` (`ShardSlot`, `SeatAnchor`, `EyeAnchor`, `AlertAnchor`, `NameAnchor`, `Slot1`..`Slot5`). Анимаций в env/props/deck нет.
- **Существа (ice, avatar).** Меш скинится жёстко (вес 1.0 на одну кость): в Godot корень `Node3D` -> `Skeleton` (`Node3D`) ->
  `Skeleton3D` (кости по имени из таблицы) -> `Mesh`; `AnimationPlayer` лежит рядом с `Skeleton`, в корне. Кости ≤ 20 (у Soft ICE 8,
  у Black ICE 12, у аватара 9). Клипы короткие и периодические (последний ключ равен первому, 30 кадров/с), имена по ТЗ: `idle`,
  `patrol` (Soft); `idle`, `hunt`, `catch` (Black). В самом .glb петли нет — `patch_imports.py` прописывает `loop_mode = 1` в
  `.glb.import`, и в Godot клипы зациклены; метки существ статичны (не следуют за костями), Core Black ICE пульсирует масштабом.
- **Жетоны и дека.** `deck/daemon_<EFFECT>.glb` — имя эффекта как в `DaemonEffect` (заглавными), в слот встаёт меткой `SlotN`.
- **Лицо.** Лицо предмета (дверца, линза, арка, внутренняя сторона стены) смотрит в **+Z**: так его видит игрок, смотрящий вдоль -Z
  (вперёд в Godot, см. `NodeLayout`). Существа и сидящий (кресло, ICE, аватар) смотрят вперёд, то есть в **-Z**.
- **Сетка.** Модули окружения — ячейка 2x2 м, origin на полу в центре ячейки. Стена стоит на крае ячейки z=-1 и входит внутрь на
  0,2 м; на другие края — поворотом вокруг Y на 90/180/270. Комната узла 16x16 м из `NodeLayout` — 8x8 ячеек, центры ячеек в нечётных
  координатах (x = -7…7, z = -13…1).
- **Тиры.** BASE, HARD, NIGHTMARE — те же меши, разные материалы: `<имя>.glb` (BASE), `<имя>_hard.glb`, `<имя>_nightmare.glb`.
  Тир меняет цвет тела и неон (бирюзовый, оранжевый, красный). Число треугольников у трёх файлов одинаковое (проверяет `check_budget.py`).
- **Материалы.** Один тёмный плоский «корпус» (`env_body_<ТИР>`, `prop_body`) и один неон (`env_neon_<ТИР>`, `prop_neon_*`):
  `base_color` и `emission` одного цвета (`KHR_materials_emissive_strength`, Godot читает как `emission_energy_multiplier`).
  **Сила свечения.** Glow в Mobile не включаем (дорого для Pico), а без него каналы выше 1,0 обрезаются, и цвет уезжает: оранжевый на силе
  2,2 становится жёлтым (оттенок 49 градусов вместо 29), зелёный — бирюзовым, красный — розовым. Поэтому: **сигнальные цвета `warn`, `ok`,
  `bad` у окружения и предметов — сила 1,0** (тиры HARD и NIGHTMARE окружения, ворота `lockdown_gate`, закрытое и открытое хранилище, закрытый портал, датчик,
  пояс зашифрованного шарда; при 1,0 Blender расширение не пишет — множитель по умолчанию 1). Нейтральный бирюзовый `acc` силу выше 1,0
  переносит (оттенок не меняется, только светлеет): 1,6 у окружения BASE, 2,2 у портала, кресла, аватара и деки. Жёлтое ядро шарда (`money`)
  осталось на 2,2: так оно чисто жёлтое (60 градусов) и отличается от оранжевого (30-35 градусов). ICE оставлены на 1,4 (на снимке читаются), жетоны
  демонов и мёртвая дека — 1,0. Сила задаётся в `palette.py` (`NEON_*`, `neon_strength`), снимок «до/после» — `previews/glow_compare.png`. Без текстур,
  прозрачности, теней, вершинных цветов; обратные грани отсекаются. Единственное исключение по UV — плоскость `Screen` деки (развёртка
  есть, картинок нет).
- **Палитра** (из `docs/ux/ui-style-guide.md`, смысл цвета тот же): `acc #5EF6FF` — интерактивное, тир BASE, портал, кресло;
  `warn #FF9F43` — «ждёт действия», тир HARD, закрытое хранилище, зашифрованный шард; `bad #FF5A50` — опасность, тир NIGHTMARE,
  датчик, запертые ворота; `money #F5D547` — добыча (шард); `ok #43F08F` — открытое хранилище; `chrome #C65A52` — мёртвая дека.
  Тела: BASE `#15272B`, HARD `#2B1F14`, NIGHTMARE `#2E1215`, предметы `#2A2D31`, Soft ICE `#2B2118`, Black ICE `#1B1317`. Лайм гайдлайна
  (экраны взлома) в мире не используется. ICE: Soft — `warn`, Black — `bad`; аватар — `acc`; жетоны демонов — по цвету на эффект
  (`money`, `acc`, `ink #E2F4F0`, `label #F08A80`, `ink2 #9DB3AF`, `bad`, `warn`, `ok`, см. таблицу deck).
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
            out.append("\n\\* ТЗ числа не задаёт; %s." % FOOTNOTES.get(group, "принят потолок 2000 как для остальных предметов"))
    out.append("\nМетки (`Node3D`) и их положение: `ShardSlot` у хранилищ, `SeatAnchor` и `EyeAnchor` у кресла, `AlertAnchor` у ICE, "
               "`NameAnchor` у аватара, `Slot1`..`Slot5` у деки (см. таблицы групп).")
    path = os.path.join(MODELS, "MANIFEST.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print("записан", os.path.relpath(path, os.path.dirname(MODELS)), "— ассетов:", len(infos))


if __name__ == "__main__":
    main()
