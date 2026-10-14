#!/bin/bash
# Root-часть самолечения USB devbox: программное «выдернуть и воткнуть» хаба VIA Labs (2109:*), на котором сидят очки Pico.
# Ставится в /usr/local/sbin/box-usb-recover скриптом install-usb-recover.sh (один раз, руками владельца: нужен пароль sudo);
# дальше user-страж `ctl.sh usb-watch` зовёт его через `sudo -n`. Делает только это: deauthorize → authorize корневых
# устройств хаба (ядро заново перечисляет хаб и всё под ним). Аргументов не принимает, ничего больше не трогает.
set -u
n=0
for d in /sys/bus/usb/devices/*; do
  b=$(basename "$d")
  case $b in *:*|*.*) continue;; esac   # интерфейсы (2-4:1.0) и устройства под хабом (2-4.1) — не корни
  [ -f "$d/idVendor" ] && [ "$(cat "$d/idVendor")" = 2109 ] || continue
  echo 0 >"$d/authorized" && sleep 2 && echo 1 >"$d/authorized" && n=$((n + 1))
done
echo "box-usb-recover: переподключено хабов VIA: $n"
