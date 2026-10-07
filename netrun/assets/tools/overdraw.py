#!/usr/bin/env python3
"""Перерисовка по кадрам карты `preview_capture.gd --overdraw=<слои>` (запускается на devbox, нужен Pillow).

Каждый прозрачный фрагмент выбранного слоя даёт вклад OD_STEP = 1/32 (линейно) на чёрном фоне, поэтому число слоёв в пикселе
n = max(R, G, B) в линейном пространстве / OD_STEP (sRGB-кодирование кадра снимаем обратным преобразованием). Предел точности — 32 слоя (белый).
Вход: каталог с подкаталогами по слоям (`all`, `streaks`, …), в каждом кадры PNG. Выход: таблица слой × кадр: среднее, p95, p99, максимум слоёв на пиксель,
доля пикселей с > 8 слоями; в конце строка по слою: среднее по кадрам. Фрагменты за пределами экрана и скрытые глубиной (непрозрачные плиты) не считаются.
"""
import os
import sys
import warnings

from PIL import Image

STEP = 1.0 / 32.0


def lin(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


LUT = [lin(i) / STEP for i in range(256)]


def layers(path):
    im = Image.open(path).convert("RGB")
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")  # getdata объявлен устаревшим в Pillow 14; на devbox пока рабочий
        px = im.getdata()
        ns = sorted(max(LUT[r], LUT[g], LUT[b]) for r, g, b in px)
    n = len(ns)
    return {
        "mean": sum(ns) / n,
        "p95": ns[int(n * 0.95)],
        "p99": ns[int(n * 0.99)],
        "max": ns[-1],
        "gt8": 100.0 * sum(1 for v in ns if v > 8.0) / n,
    }


def main():
    root = sys.argv[1]
    cats = sorted((c for c in os.listdir(root) if os.path.isdir(os.path.join(root, c))), key=lambda c: (c != "all", c))
    print(f"{'слой':<12} {'кадр':<18} {'среднее':>8} {'p95':>6} {'p99':>6} {'макс':>6} {'>8, %':>6}")
    for cat in cats:
        d = os.path.join(root, cat)
        rows = []
        for f in sorted(os.listdir(d)):
            if not f.endswith(".png") or f == "grid.png":
                continue
            r = layers(os.path.join(d, f))
            rows.append(r)
            print(f"{cat:<12} {f[:-4]:<18} {r['mean']:8.2f} {r['p95']:6.1f} {r['p99']:6.1f} {r['max']:6.1f} {r['gt8']:6.1f}")
        if rows:
            m = sum(r["mean"] for r in rows) / len(rows)
            print(f"{cat:<12} {'— среднее —':<18} {m:8.2f}")
    print("Слоёв ≥ 31 в пикселе — насыщение шкалы (белый), реальное число больше.")


if __name__ == "__main__":
    main()
