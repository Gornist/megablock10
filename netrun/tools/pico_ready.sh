#!/usr/bin/env bash
# Снять известные системные окна Pico безопасными кнопками, не меняющими настройки: «Войти в VR (текущая граница)», «Перезапустить отслеживание»,
# «Продолжить» (окно «Требуется контроллер»). Незнакомое окно — выход 3 с его текстом. Нужна бронь очков (box.sh pico wake).
. ~/netrun-env.sh
S=${PICO_SERIAL:-PA8110MGH4261073G}
python3 - "$S" <<'PY'
import re, subprocess, sys, time
S = sys.argv[1]
ALLOWED = ("Войти в VR (текущая граница)", "Перезапустить отслеживание", "Продолжить")
def adb(*a):
    return subprocess.run(["adb", "-s", S, *a], capture_output=True, text=True, stdin=subprocess.DEVNULL).stdout
def dump():
    adb("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    x = adb("shell", "cat", "/sdcard/ui.xml")
    out = []
    for n in re.findall(r"<node [^>]*>", x):
        g = lambda k: (re.search(k + r'="([^"]*)"', n) or [None, ""])[1]
        # окно «Установить границу игры» рисует com.pvr.seethrough.setting (Unity, один узел «Game view» без кнопок): текстом не нажать — незнакомое окно
        label = g("text") or (g("content-desc") if g("package") == "com.pvr.seethrough.setting" else "")
        if g("package") in ("com.picovr.systemext", "com.pvr.seethrough.setting") and label:
            out.append((label, g("clickable") == "true", g("bounds")))
    return out
for i in range(8):
    nodes = dump()
    if not nodes:
        print("ready: системных окон нет"); sys.exit(0)
    btn = next((n for n in nodes if n[1] and n[0] in ALLOWED), None)
    if btn is None:
        print("НЕЗНАКОМОЕ ОКНО:", " | ".join(t for t, _, _ in nodes)); sys.exit(3)
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", btn[2])
    x = (int(m[1]) + int(m[3])) // 2; y = (int(m[2]) + int(m[4])) // 2
    print(f"ready: жму «{btn[0]}» ({x},{y})")
    adb("shell", "input", "tap", str(x), str(y))
    time.sleep(4)
print("ready: окна не уходят после 8 попыток"); sys.exit(4)
PY
