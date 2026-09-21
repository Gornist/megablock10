#!/bin/bash
# Грубый замер нагрузки матрицы взлома: загрузка процессора приложением (top) за один полный автоматический взлом на эмуляторе Alice против простоя.
# Кадры (dumpsys gfxinfo) на эмуляторе без окна не считаются вовсе, а опрос экрана (uiautomator) сам подвешивает интерфейс — поэтому меряем CPU
# процесса без единого опроса экрана на время замера. Эмулятор рисует программно, цифры не переносятся на телефон 1:1: годятся для сравнения
# «до/после» правки и для поиска аномалий (простой должен быть около нуля). Нужен поднятый стенд (./up.sh). PERF_SECONDS — длительность окна.
source "$(dirname "$0")/lib.sh"
QR=$(container perf-1 "Perf" HARD Perf 1)
[ -n "$QR" ] || die "не создался контейнер"
set_config $A clock 1; set_config $A timer 4; autosolve $A true; set_config $A step 900
dbg $A DEBUG_SET --es cooldowns reset --es ram 9
dbg $A DEBUG_SET --es daemon "Datamine:1C,FF:2:MINER" >/dev/null 2>&1
# Запуск взлома по шагам БЕЗ опроса экрана на время замера: uiautomator dump подвешивает интерфейс на программном рендере эмулятора и портит цифры.
open_deck $A
dbg $A DEBUG_QR --es qr "$QR"
wait_until 15 screen_has $A "Datamine" || die "не открылся выбор демонов"
tap_text $A "Datamine" >/dev/null; sleep 0.5
cpu() { # cpu <секунд> — средняя загрузка процесса приложения (% одного ядра) за окно
  local pid; pid=$(adb_ $A shell pidof $PKG | tr -d '\r' | awk '{print $1}')
  adb_ $A shell "top -b -d 1 -n $1 -p $pid" 2>/dev/null | tr -d '\r' | awk -v pid="$pid" '$1==pid {s+=$9; n++} END {if (n) printf "%.1f%% (замеров %d)\n", s/n, n; else print "нет данных"}'
}
echo "простой (экран взлома открыт, взлом не запущен): $(cpu 8)"
tap_text $A "Взломать контейнер" >/dev/null
echo "взлом идёт: $(cpu "${PERF_SECONDS:-30}")"
sleep 5
screen_has $A "Взлом завершён\|Взлом частично\|Взлом провален" && echo "результат взлома: экран итога виден" || echo "(итога на экране нет — увеличьте PERF_SECONDS)"
