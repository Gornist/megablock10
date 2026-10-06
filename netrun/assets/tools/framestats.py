#!/usr/bin/env python3
"""Числовые метрики кадров «Сети»: сравнивать с референсом цифрами, а не глазами (картинки в контекст не нужны).

Запуск — через `pipeline.sh stats <кадр|каталог> ... [--ref <кадр>]` (на devbox есть Pillow, на Mac нет), напрямую:
    python3 framestats.py [--ref ref.png ...] кадр.png|каталог ...
Метрики считаются по кадру, уменьшенному до 320 px по ширине (чёрная плашка с подписью CDPR внизу референсов отрезается: нижние 6%):
  lum    средняя яркость 0..100 (0 — чёрный кадр)
  dark   доля почти чёрных пикселей (яркость < 3), %. Замер 06.10 по двум референсам CDPR: ≈ 0 — у них нигде нет чистого чёрного, везде тёмная
         бирюзовая дымка; у наших кадров 11–36 %: пустота между плитами у нас чернее, чем в референсе
  lit    доля светящихся пикселей (яркость > 45), %
  cyan   доля бирюзы среди светящихся, % (оттенок 160–205°) — окружение BASE должно быть ≥ 70
  blue   доля синего среди светящихся, % (оттенок 206–260°) — синева = тир HARD, в BASE ≈ 0–15
  red    доля красного среди ВСЕХ пикселей, % — только люди/ICE; в кадре окружения без существ ≈ 0
  hor    яркость полосы горизонта (кадр по высоте 38–58%) относительно средней по кадру, ×  (> 1,2: дымка у горизонта есть)
  topbot яркость верхней трети / нижней трети (потолок против пола), ×
Код выхода 0; пороги — ориентиры, вердикт выносит человек (или skill netrun-assets)."""
import colorsys
import glob
import os
import sys
import warnings

from PIL import Image

W = 320


def load(path):
    im = Image.open(path).convert("RGB")
    h = im.height
    im = im.crop((0, 0, im.width, int(h * 0.94)))  # плашка с подписью внизу референсов
    return im.resize((W, max(1, round(im.height * W / im.width))), Image.BILINEAR)


def lum_of(r, g, b):
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0 * 100.0


def stats(path):
    im = load(path)
    w, h = im.size
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")  # getdata объявлен устаревшим в Pillow 14; на devbox пока рабочий
        px = list(im.getdata())
    n = len(px)
    lum_sum = dark = lit = cyan = blue = red = 0
    rows = [0.0] * h
    for i, (r, g, b) in enumerate(px):
        lu = lum_of(r, g, b)
        rows[i // w] += lu
        lum_sum += lu
        if lu < 3.0:
            dark += 1
        hh, ss, vv = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        deg = hh * 360.0
        if r > 90 and r > 1.7 * g and r > 1.7 * b:
            red += 1
        if lu > 45.0 and ss > 0.25:
            lit += 1
            if 160 <= deg <= 205:
                cyan += 1
            elif 206 <= deg <= 260:
                blue += 1
        elif lu > 45.0:
            lit += 1
    mean = lum_sum / n
    row_mean = [v / w for v in rows]
    hor = sum(row_mean[int(h * 0.38):int(h * 0.58)]) / max(1, int(h * 0.58) - int(h * 0.38))
    top = sum(row_mean[: h // 3]) / max(1, h // 3)
    bot = sum(row_mean[-(h // 3):]) / max(1, h // 3)
    return {
        "lum": mean,
        "dark": 100.0 * dark / n,
        "lit": 100.0 * lit / n,
        "cyan": 100.0 * cyan / max(1, lit),
        "blue": 100.0 * blue / max(1, lit),
        "red": 100.0 * red / n,
        "hor": hor / max(mean, 0.01),
        "topbot": top / max(bot, 0.01),
    }


KEYS = ["lum", "dark", "lit", "cyan", "blue", "red", "hor", "topbot"]


def fmt(name, s):
    return "%-22s" % name[:22] + "".join("%8.1f" % s[k] if k != "hor" and k != "topbot" else "%8.2f" % s[k] for k in KEYS)


def expand(items):
    out = []
    for it in items:
        if os.path.isdir(it):
            out += [f for f in sorted(glob.glob(it + "/*.png")) if not f.endswith("grid.png")]
        else:
            out.append(it)
    return out


def main(argv):
    refs, files, i = [], [], 0
    while i < len(argv):
        if argv[i] == "--ref":
            refs.append(argv[i + 1])
            i += 2
        else:
            files.append(argv[i])
            i += 1
    files = expand(files)
    if not files:
        print("framestats: нет кадров", file=sys.stderr)
        return 2
    print("%-22s" % "кадр" + "".join("%8s" % k for k in KEYS))
    ref_stats = []
    for r in expand(refs):
        s = stats(r)
        ref_stats.append(s)
        print(fmt("REF " + os.path.basename(r), s))
    for f in files:
        s = stats(f)
        print(fmt(os.path.basename(f), s))
        for rs in ref_stats[:1]:
            print("%-22s" % "  Δ к первому REF" + "".join("%+8.1f" % (s[k] - rs[k]) if k not in ("hor", "topbot") else "%+8.2f" % (s[k] - rs[k]) for k in KEYS))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
