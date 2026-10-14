#!/bin/bash
# Один раз, руками владельца (нужен пароль sudo): sudo bash ~/box/repo/scripts/box/install-usb-recover.sh
# Что делает ровно:
#   1) кладёт usb-recover.sh в /usr/local/sbin/box-usb-recover (владелец root — nick подменить его не может);
#   2) разрешает пользователю nick запускать именно этот файл через sudo без пароля (/etc/sudoers.d/devbox-usb, проверка visudo).
# Откат: sudo rm /usr/local/sbin/box-usb-recover /etc/sudoers.d/devbox-usb
set -eu
[ "$(id -u)" = 0 ] || { echo "нужен sudo: sudo bash $0"; exit 1; }
SRC=$(cd "$(dirname "$0")" && pwd)/usb-recover.sh
[ -f "$SRC" ] || { echo "нет $SRC"; exit 1; }
install -o root -g root -m 755 "$SRC" /usr/local/sbin/box-usb-recover
F=/etc/sudoers.d/devbox-usb
echo 'nick ALL=(root) NOPASSWD: /usr/local/sbin/box-usb-recover' >"$F.tmp"
chmod 440 "$F.tmp"
visudo -cf "$F.tmp" >/dev/null || { rm -f "$F.tmp"; echo "sudoers не прошёл проверку — ничего не поставлено"; exit 1; }
mv "$F.tmp" "$F"
echo "готово: /usr/local/sbin/box-usb-recover и $F"
