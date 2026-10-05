#!/bin/bash
# Телефоны, подключённые по USB к devbox (adb там): короткие команды вместо длинных ssh-цепочек. Серверный adb общий — не убивать (adb kill-server).
#   scripts/phone.sh devices                         — устройства и модели
#   scripts/phone.sh install <серийник> [apk]        — чистая установка (с удалением прежней) и разрешения; apk по умолчанию — из ~/wt-dbx-*/ последней сборки assembleDebug
#   scripts/phone.sh prov <серийник> <Позывной> <Фракция> [баланс] [RAM] — выдача персонажа через QR-путь приложения (DEBUG_QR), адрес сервера — из сборки
#   scripts/phone.sh provlive <серийник> <Позывной> <Фракция> [баланс] [RAM] — то же, но QR выдаёт живой коллектор на devbox (~/live-collector: env, master-token.txt;
#                                                      порт 2527): телефон получает его адрес и код игры, синк идёт на этот коллектор
#   scripts/phone.sh qr <серийник> <строка QR>       — «отсканировать» QR (экран выдачи/Кибердека должен быть открыт)
#   scripts/phone.sh shot <серийник> [файл.png]      — снимок экрана → файл на Mac (путь печатается; смотреть Read'ом)
#   scripts/phone.sh ui <серийник>                   — текст экрана (uiautomator): строки «(x,y) подпись», у нажимаемых — [click]; дешевле снимка. Не видит оверлеи (входящий звонок)
#   scripts/phone.sh taptext <серийник> <подстрока>  — тап по центру элемента, чья подпись содержит подстроку (без учёта регистра); LONG=1 — долгое касание (оверлеи Xiaomi)
#   scripts/phone.sh tap <серийник> <x> <y>          — касание в пикселях оригинала (снимок масштабируется: x_ориг = x_на_снимке × 1,2 при 897 px ширины)
#   scripts/phone.sh log <серийник> [шаблон]         — журнал приложения (файл mb10-current.log), по шаблону grep -E
# Координаты из `ui` брать ПОСЛЕ набора текста: с клавиатурой кнопки сдвигаются. Внутри ленты чата координаты искажены — смотреть снимок.
# Xiaomi: нужны «Установка через USB» и «Отладка по USB (настройки безопасности)», иначе нет input и pm grant.
# Гарнитуру Pico (A8110) и чужие приложения не трогаем без разрешения владельца.
set -u
ADB='$HOME/android-sdk/platform-tools/adb'; PKG=com.megablok10.app; cmd=${1:-}; S=${2:-}
r() { ssh -o ConnectTimeout=10 -o BatchMode=yes devbox "ADB=$ADB; $*"; }
# Разбор дампа uiautomator (XML на stdin): «центр подпись» нужных узлов; аргумент "list" — все с текстом или нажимаемые, иначе первый с подстрокой.
uiparse() { python3 -c '
import sys, re, xml.etree.ElementTree as ET
q = sys.argv[1]
try:
    tree = ET.parse(sys.stdin)
except ET.ParseError:
    sys.exit("uiautomator не вернул экран (устройство не подключено или экран занят системным окном)")
for n in tree.iter("node"):
    txt = n.get("text") or n.get("content-desc") or ""
    click = n.get("clickable") == "true"
    m = re.findall(r"\d+", n.get("bounds"))
    x, y = (int(m[0]) + int(m[2])) // 2, (int(m[1]) + int(m[3])) // 2
    if q == "list":
        if txt or click:
            print(("[click] " if click else "        ") + "(%d,%d) %s" % (x, y, txt[:70]))
    elif q.lower() in txt.lower():
        print("%d %d" % (x, y)); break
' "$1"; }
uidump() { r "\$ADB -s $S shell uiautomator dump /sdcard/mb10-ui.xml >/dev/null 2>&1; \$ADB -s $S exec-out cat /sdcard/mb10-ui.xml"; }
case $cmd in
  devices) r '$ADB devices -l' ;;
  install) APK=${3:-}
    r "APK=\${APK:-$APK}; [ -n \"\$APK\" ] || APK=\$(ls -t ~/wt-dbx-*/app/build/outputs/apk/debug/app-debug.apk | head -1); echo \$APK
       \$ADB -s $S uninstall $PKG >/dev/null 2>&1; \$ADB -s $S install -r \$APK | tail -1
       for p in POST_NOTIFICATIONS RECORD_AUDIO CAMERA NEARBY_WIFI_DEVICES; do \$ADB -s $S shell pm grant $PKG android.permission.\$p >/dev/null 2>&1; done
       \$ADB -s $S shell input keyevent KEYCODE_WAKEUP; \$ADB -s $S shell am start -n $PKG/.MainActivity | tail -1" ;;
  prov) CS=${3:?позывной}; FAC=${4:?фракция}; BAL=${5:-300}; RAM=${6:-8}
    QR=$(python3 -c 'import base64,sys,uuid;b=lambda t:base64.b64encode(t.encode()).decode();print("MB10:PROV:v1:%s:%s:%s:%s:%s:%s:%s"%(uuid.uuid4().hex[:12],b(""),b(""),b(sys.argv[1]),b(sys.argv[2]),sys.argv[3],sys.argv[4]))' "$CS" "$FAC" "$BAL" "$RAM")
    exec "$0" qr "$S" "$QR" ;;
  provlive) CS=${3:?позывной}; FAC=${4:?фракция}; BAL=${5:-300}; RAM=${6:-8}
    # Вход мастера, создание кода персонажа и подача QR на телефон — всё на devbox, токен и код игры в чат/на Mac не попадают.
    ssh -o ConnectTimeout=10 -o BatchMode=yes devbox bash -s -- "$S" "$CS" "$FAC" "$BAL" "$RAM" "$PKG" <<'REMOTE'
S=$1; CS=$2; FAC=$3; BAL=$4; RAM=$5; PKG=$6
A=$HOME/android-sdk/platform-tools/adb; D=$HOME/live-collector; B=http://127.0.0.1:2527
[ -f "$D/master-token.txt" ] || { echo "provlive: нет $D/master-token.txt — коллектор не поднят?"; exit 1; }
TOK=$(grep -A1 'Токен для входа' "$D/master-token.txt" | tail -1)
SES=$(curl -s -X POST $B/api/auth/login -H 'content-type: application/json' -d "{\"name\":\"Мастер\",\"token\":\"$TOK\"}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["sessionToken"])') || { echo "provlive: вход мастера не удался"; exit 1; }
R=$(curl -s -X POST $B/api/provisions -H "authorization: Bearer $SES" -H 'content-type: application/json' -d "{\"callsign\":\"$CS\",\"faction\":\"$FAC\",\"balance\":$BAL,\"ram\":$RAM}")
QR=$(echo "$R" | python3 -c 'import json,sys;print(json.load(sys.stdin)["qr"])') || { echo "provlive: коллектор не выдал код: $R" | cut -c1-200; exit 1; }
$A -s "$S" shell "am broadcast -f 0x20 -n $PKG/$PKG.qr.DebugQrReceiver -a $PKG.DEBUG_QR --es qr '$QR'" >/dev/null
sleep 6
LINE=$($A -s "$S" shell "grep -E 'provision\.(done|refused)' /sdcard/Android/data/$PKG/files/logs/mb10-current.log | tail -1" | cut -c1-200)
case "$LINE" in
  *provision.done*) echo "provlive: $CS выдан и применён (${LINE##* })" ;;
  *) echo "provlive: $CS — применения не видно (экран выдачи открыт? персонаж уже есть?): ${LINE:-в журнале нет provision.*}"; exit 1 ;;
esac
REMOTE
    ;;
  qr) r "\$ADB -s $S shell \"am broadcast -f 0x20 -n $PKG/$PKG.qr.DebugQrReceiver -a $PKG.DEBUG_QR --es qr '${3:?строка QR}'\" | tail -1" ;;
  shot) OUT=${3:-${TMPDIR:-/tmp}/phone-$S.png}; r "\$ADB -s $S exec-out screencap -p" > "$OUT" && echo "$OUT" ;;
  ui) uidump | uiparse list ;;
  taptext) Q=${3:?подстрока}
    XY=$(uidump | uiparse "$Q")
    [ -n "$XY" ] || { echo "taptext: нет элемента «$Q»"; exit 1; }
    set -- $XY
    if [ "${LONG:-0}" = 1 ]; then r "\$ADB -s $S shell input swipe $1 $2 $1 $2 180"; echo "taptext: «$Q» → $1 $2 (долгое)"
    else r "\$ADB -s $S shell input tap $1 $2"; echo "taptext: «$Q» → $1 $2"; fi ;;
  tap) r "\$ADB -s $S shell input tap ${3:?x} ${4:?y}" ;;
  log) r "\$ADB -s $S shell \"grep -E '${3:-.}' /sdcard/Android/data/$PKG/files/logs/mb10-current.log | tail -40\"" ;;
  *) sed -n 2,17p "$0" ;;
esac
