#!/usr/bin/env python3
"""Разбор дампа uiautomator очков Pico для `ctl.sh pico ready` (XML на stdin). Только чтение: ничего не нажимает.

Печатает одну строку (поля через TAB):
  KNOWN  <id>  <x> <y>  <кнопка>  <заголовок>  — на экране известное безопасное окно, кнопку можно нажать в центре (x, y)
  NONE   <тексты через " | ">                  — известных окон нет (тексты — чтобы вердикт «не готово» был читаемым)

Белый список (решение владельца 13.10 через Pipeline). Окно считается известным, только если совпали ВСЕ признаки:
заголовок (подстрока в любом тексте), точный текст кнопки и пакет окна. Кнопку ищем по тексту, не по координатам.
Чего нет в списке — не нажимается никогда: «Выключить отслеживание», «Сбросить границу», «Настраиваемая граница»,
«Включить режим прозрачности», «Отмена», любые настройки. FORBIDDEN дублирует это как страховку от правки списка.
"""
import re
import sys
import xml.etree.ElementTree as ET

SYSTEM_PKGS = ("com.picovr.", "com.pvr.")

RULES = [
    # id, подстроки заголовка (любая; пусто — не требуется), точный текст кнопки, префиксы пакета
    # Заголовок окна границы неизвестен (не наблюдался в дампе) — опираемся на точный текст кнопки и системный пакет.
    ("boundary", [], "Войти в VR (текущая граница)", SYSTEM_PKGS),
    ("too_dark", ["Слишком темно"], "Перезапустить отслеживание", SYSTEM_PKGS),
    ("need_controller", ["Требуется контроллер"], "Продолжить", SYSTEM_PKGS),
]

FORBIDDEN = (
    "выключить отслеживание", "сбросить границу", "настраиваемая граница", "включить режим прозрачности",
    "отмена", "настройк", "сброс", "удалить", "выключить", "отключить",
)


def center(bounds):
    m = re.findall(r"\d+", bounds or "")
    if len(m) < 4:
        return None
    x0, y0, x1, y1 = (int(v) for v in m[:4])
    if x1 <= x0 or y1 <= y0:
        return None
    return (x0 + x1) // 2, (y0 + y1) // 2


def main():
    try:
        root = ET.parse(sys.stdin).getroot()
    except ET.ParseError:
        print("NONE\t(uiautomator не вернул экран)")
        return
    nodes = []
    for n in root.iter("node"):
        txt = (n.get("text") or n.get("content-desc") or "").strip()
        if txt:
            nodes.append((txt, n.get("bounds"), n.get("package") or ""))
    texts = [t for t, _, _ in nodes]
    for rid, titles, button, prefixes in RULES:
        if any(f in button.lower() for f in FORBIDDEN):
            continue  # страховка: запрещённое в белый список не попадает
        if titles and not any(any(t.lower() in x.lower() for x in texts) for t in titles):
            continue
        for txt, bounds, pkg in nodes:
            if txt != button or not pkg.startswith(prefixes):
                continue
            c = center(bounds)
            if c is None:
                continue
            title = next((x for x in texts if titles and titles[0].lower() in x.lower()), "")
            print("KNOWN\t%s\t%d %d\t%s\t%s" % (rid, c[0], c[1], button, title))
            return
    print("NONE\t" + " | ".join(t[:60] for t in texts[:12]))


if __name__ == "__main__":
    main()
