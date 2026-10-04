#!/bin/bash
# Телефоны, подключённые по USB к devbox (adb там): короткие команды вместо длинных ssh-цепочек. Серверный adb общий — не убивать (adb kill-server).
#   scripts/phone.sh devices                         — устройства и модели
#   scripts/phone.sh install <серийник> [apk]        — чистая установка (с удалением прежней) и разрешения; apk по умолчанию — из ~/wt-dbx-*/ последней сборки assembleDebug
#   scripts/phone.sh prov <серийник> <Позывной> <Фракция> [баланс] [RAM] — выдача персонажа через QR-путь приложения (DEBUG_QR)
#   scripts/phone.sh qr <серийник> <строка QR>       — «отсканировать» QR (экран выдачи/Кибердека должен быть открыт)
#   scripts/phone.sh shot <серийник> [файл.png]      — снимок экрана → файл на Mac (путь печатается; смотреть Read'ом)
#   scripts/phone.sh tap <серийник> <x> <y>          — касание в пикселях оригинала (снимок масштабируется: x_ориг = x_на_снимке × 1,2 при 897 px ширины)
#   scripts/phone.sh log <серийник> [шаблон]         — журнал приложения (файл mb10-current.log), по шаблону grep -E
# Гарнитуру Pico (A8110) и чужие приложения не трогаем без разрешения владельца.
set -u
ADB='$HOME/android-sdk/platform-tools/adb'; PKG=com.megablok10.app; cmd=${1:-}; S=${2:-}
r() { ssh -o ConnectTimeout=10 -o BatchMode=yes devbox "ADB=$ADB; $*"; }
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
  qr) r "\$ADB -s $S shell \"am broadcast -f 0x20 -n $PKG/$PKG.qr.DebugQrReceiver -a $PKG.DEBUG_QR --es qr '${3:?строка QR}'\" | tail -1" ;;
  shot) OUT=${3:-${TMPDIR:-/tmp}/phone-$S.png}; r "\$ADB -s $S exec-out screencap -p" > "$OUT" && echo "$OUT" ;;
  tap) r "\$ADB -s $S shell input tap ${3:?x} ${4:?y}" ;;
  log) r "\$ADB -s $S shell \"grep -E '${3:-.}' /sdcard/Android/data/$PKG/files/logs/mb10-current.log | tail -40\"" ;;
  *) sed -n 2,11p "$0" ;;
esac
