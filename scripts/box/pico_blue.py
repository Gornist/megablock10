#!/usr/bin/env python3
"""Поиск синей кнопки окна границы Pico на скриншоте (для `ctl.sh pico ready`). Только чтение файла, ничего не нажимает.

    pico_blue.py <screencap.png>      →  «x y w h»  (центр и размер блока в пикселях оригинала) или «NONE <причина>»

Раскладка карточки «Установить границу игры» зависит от состояния границы (на кадре 13.10 20:26 кнопка «Войти в VR (текущая
граница)» на (1145, 1523) при 4320×2160, у другого варианта карточки — выше), поэтому фиксированные координаты ненадёжны. Окно — Unity без
нод в uiautomator, поэтому ищем по цвету: самый крупный связный синий блок (≈ RGB 58,131,224) в ЛЕВОЙ половине кадра (левый глаз),
по форме кнопки (широкий, невысокий). Прочие кнопки карточки («Сбросить неподвижную границу», «Настраиваемая граница») серые и под
критерий не попадают; голубая линия границы (cyan, g > 190) — тоже нет. Нет подходящего блока — NONE, нажимать нечего.
"""
import sys

from PIL import Image

STEP = 4  # уменьшение: 4320x2160 → 1080x540, поиск по ~290k пикселей левой половины


def is_blue(p):
    r, g, b = p[0], p[1], p[2]
    return r < 120 and 90 <= g <= 175 and b >= 180 and (b - r) >= 100 and (b - g) >= 40


def main():
    if len(sys.argv) != 2:
        print("NONE нужен путь к PNG")
        return
    try:
        im = Image.open(sys.argv[1]).convert("RGB")
    except Exception as e:  # noqa: BLE001 — любой сбой чтения = «не нашли», не падаем
        print("NONE не прочитал PNG: %s" % str(e)[:60])
        return
    W, H = im.size
    if (W, H) != (4320, 2160):
        print("NONE экран %dx%d, ожидался 4320x2160" % (W, H))
        return
    sm = im.reduce(STEP)
    w, h = sm.size
    half = w // 2
    px = sm.load()
    seen = [[False] * half for _ in range(h)]
    best = None
    for y0 in range(h):
        for x0 in range(half):
            if seen[y0][x0] or not is_blue(px[x0, y0]):
                continue
            stack = [(x0, y0)]
            seen[y0][x0] = True
            n = 0; sx = sy = 0
            minx = maxx = x0
            miny = maxy = y0
            while stack:
                x, y = stack.pop()
                n += 1; sx += x; sy += y
                minx, maxx = min(minx, x), max(maxx, x)
                miny, maxy = min(miny, y), max(maxy, y)
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < half and 0 <= ny < h and not seen[ny][nx] and is_blue(px[nx, ny]):
                        seen[ny][nx] = True
                        stack.append((nx, ny))
            bw, bh = maxx - minx + 1, maxy - miny + 1
            # кнопка: достаточно большая, широкая и невысокая, заполнена по большей части (не тонкая линия)
            if n >= 300 and bw >= 30 and bh >= 6 and 2.5 <= bw / bh <= 14 and n / (bw * bh) >= 0.25:
                if best is None or n > best[0]:
                    best = (n, minx, miny, maxx, maxy, sx, sy)
    if best is None:
        print("NONE синего блока-кнопки в левой половине кадра нет")
        return
    n, minx, miny, maxx, maxy, sx, sy = best
    cx = int((sx / n + 0.5) * STEP)  # центроид, а не центр bbox: карточка наклонена
    cy = int((sy / n + 0.5) * STEP)
    print("%d %d %d %d" % (cx, cy, (maxx - minx + 1) * STEP, (maxy - miny + 1) * STEP))


if __name__ == "__main__":
    main()
