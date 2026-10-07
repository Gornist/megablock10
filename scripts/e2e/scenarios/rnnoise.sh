#!/bin/bash
# Шумодав микрофона звонка (RNNoise): нативная библиотека загрузилась на эмуляторе и через JNI давит стационарный шум («кулер») больше чем на 10 дБ; выключатель отладочной
# командой callaudio и обратно не роняет приложение. Сам тракт звонка с реальным микрофоном на эмуляторе не проверяется (только телефоны).
source "$(dirname "$0")/../lib.sh"
echo "== rnnoise"
selftest() { adb_ $A logcat -c; dbg $A DEBUG_SET --es rnnoisetest 1; await 15 bash -c "source '$ROOT/scripts/e2e/lib.sh'; adb_ $A logcat -d -s MB10DBG | grep 'rnnoise selftest ->' | tail -1 | sed 's/.*-> //'"; }
DB=$(selftest)
check "библиотека загрузилась (не UNAVAILABLE)" test "$DB" != UNAVAILABLE -a -n "$DB"
check "стационарный шум подавлен больше чем на 10 дБ ($DB дБ)" awk -v d="$DB" 'BEGIN{exit !(d+0 >= 10)}'
dbg $A DEBUG_SET --es callaudio "rnnoise=0"; sleep 1
dbg $A DEBUG_SET --es callaudio "rnnoise=1"; sleep 1
check "приложение живо после переключения" test -n "$(adb_ $A shell pidof com.megablok10.app | tr -d '\r')"
finish
