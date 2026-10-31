#!/usr/bin/env python3
"""Сверка эталона V11 с кадрами CP2077: числа кадра и одна сетка «эталон | CP2077» ≤ 1024 px.

  python3 compare.py <каталог кадров> <каталог референса> <сетка.png> пара[,пара...]
  пара — имя_кадра:имя_референса (без .png), например wide:r376,pillar:r470,floor:r520

Числа (только Pillow, без numpy): медиана яркости L (0–255), доля пикселей ярче 128 и 200, доля «пустоты» (L < 20),
медиана цвета 5 % самых ярких пикселей, медианы цвета «холодных» и «красных» пикселей. Референс — нижние 12 % кадра
(субтитры) и правый верх (HUD) обрезаются, чтобы не считать их.
"""
import sys
from PIL import Image


def stats(path, ref=False):
    im = Image.open(path).convert("RGB")
    if ref:  # без субтитров снизу и HUD справа сверху
        w, h = im.size
        im = im.crop((0, int(h * 0.12), int(w * 0.85), int(h * 0.86)))
    im = im.resize((480, int(480 * im.height / im.width)))
    px = list(im.getdata())
    lum = sorted((0.2126 * r + 0.7152 * g + 0.0722 * b, (r, g, b)) for r, g, b in px)
    n = len(lum)
    ls = [x[0] for x in lum]
    med = ls[n // 2]
    gt128 = sum(1 for v in ls if v > 128) / n
    gt200 = sum(1 for v in ls if v > 200) / n
    void = sum(1 for v in ls if v < 20) / n
    top = [c for _, c in lum[int(n * 0.95):]]

    def mc(cs):
        if not cs:
            return "-"
        return "#%02x%02x%02x" % tuple(sorted(c[i] for c in cs)[len(cs) // 2] for i in range(3))
    cold = [c for c in px if c[2] > c[0] + 8 and sum(c) > 60]
    red = [c for c in px if c[0] > c[1] * 1.8 and c[0] > 50]
    return {"L50": med, "p90": ls[int(n * 0.9)], "p99": ls[int(n * 0.99)], ">128": gt128 * 100, ">200": gt200 * 100,
            "void": void * 100, "top5": mc(top), "cold": mc(cold), "red": mc(red), "red%": len(red) / n * 100}


def main():
    shots, refs, out, pairs = sys.argv[1], sys.argv[2], sys.argv[3], [p.split(":") for p in sys.argv[4].split(",")]
    cw, rows = 512, []
    print("%-8s %5s %4s %4s %6s %6s %5s %8s %8s %8s %5s" % ("кадр", "L50", "p90", "p99", ">128%", ">200%", "void%", "top5", "cold", "red", "red%"))
    for a, b in pairs:
        for path, ref in (("%s/%s.png" % (shots, a), False), ("%s/%s.png" % (refs, b), True)):
            s = stats(path, ref)
            print("%-8s %5.0f %4.0f %4.0f %6.1f %6.2f %5.0f %8s %8s %8s %5.1f" % (
                ("cp:" if ref else "") + (b if ref else a), s["L50"], s["p90"], s["p99"], s[">128"], s[">200"], s["void"],
                s["top5"], s["cold"], s["red"], s["red%"]))
        ims = [Image.open("%s/%s.png" % (shots, a)).convert("RGB"), Image.open("%s/%s.png" % (refs, b)).convert("RGB")]
        rows.append([im.resize((cw, cw * 9 // 16)) for im in ims])
    sheet = Image.new("RGB", (2 * cw, len(rows) * (cw * 9 // 16)))
    for i, (l, r) in enumerate(rows):
        sheet.paste(l, (0, i * l.height))
        sheet.paste(r, (cw, i * l.height))
    sheet.save(out)
    print("сетка %s %dx%d (слева эталон, справа CP2077)" % (out, sheet.width, sheet.height))


if __name__ == "__main__":
    main()
