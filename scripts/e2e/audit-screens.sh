#!/bin/bash
# Съёмка 12 экранов приложения на эмуляторе A для ревью интерфейса «до/после»: чат, тред, звонки, Кибердека, кошелёк, профиль, настройки, выбор демонов, взлом.
# Нужен поднятый стенд (./up.sh). Результат: $E2E_DIR/audit/*.png и сводный лист sheet.png (нужен ffmpeg).
source "$(dirname "$0")/lib.sh"
PKA=$(cat $E2E_DIR/pk_$A.txt); PKB=$(cat $E2E_DIR/pk_$B.txt)
mkdir -p $E2E_DIR/audit; S=$E2E_DIR/audit; rm -f $S/*.png
dbg $A DEBUG_SET --es balance 1500 --es ram 9; dbg $A DEBUG_SET --es daemon "Cipher Key:7A,E9:2:DECRYPT"; dbg $A DEBUG_SET --es daemon "Deep Miner:E9,FF:2:MINER"; dbg $A DEBUG_SET --es daemon "Black Curtain:7A,BD,55:2:BLACKOUT"
dbg $B DEBUG_SET --es say "$PKA|Готов к делу? Узел у северных ворот."; dbg $B DEBUG_SET --es pay "$PKA:100:online"; sleep 5
snap() { adb_ $A exec-out screencap -p > $S/$1.png; }
snap 01_chat_list
tap_text $A "Bob" >/dev/null; sleep 2; snap 02_thread
adb_ $A shell input tap 55 130; sleep 1.5
adb_ $A shell input tap 405 2285; sleep 2; snap 03_calls
adb_ $A shell input tap 675 2285; sleep 2; snap 04_cyberdeck_demons
tap_text $A "Шарды" >/dev/null; sleep 1.5; snap 05_cyberdeck_shards
adb_ $A shell input tap 945 2285; sleep 2; snap 06_wallet
tap_text $A "Отправить" >/dev/null; sleep 2; snap 07_wallet_send
adb_ $A shell input tap 135 2285; sleep 1.5
adb_ $A shell input tap 100 130; sleep 2; snap 08_profile
tap_text $A "Настройки" >/dev/null; sleep 2; snap 09_settings
QR=$(container au-$RANDOM "Арасака-404" HARD Arasaka 1)
adb_ $A shell input tap 55 130; sleep 1.5; adb_ $A shell input tap 675 2285; sleep 2; tap_text $A "Демоны" >/dev/null; sleep 1
dbg $A DEBUG_QR --es qr "$QR"; sleep 4; snap 10_picker
tap_text $A "Black Curtain" >/dev/null; sleep 1; tap_text $A "Deep Miner" >/dev/null; sleep 1.5; snap 11_picker_selected
set_config $A autosolve false; tap_text $A "Взломать контейнер" >/dev/null; sleep 5; snap 12_breach
ffmpeg -v error -y -pattern_type glob -i "$S/[0-9]*.png" -vf "scale=300:-1,tile=6x2" -frames:v 1 "$S/sheet.png" && echo "готово: $S/sheet.png"
