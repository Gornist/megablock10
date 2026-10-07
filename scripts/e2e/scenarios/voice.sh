#!/bin/bash
# Голосовые сообщения (app/docs/voice-messages.md): звук едет одной строкой MB10VOICE и сохраняется файлом у получателя («доставлено» — после сохранения), 60 с (≈150 КБ) доходят целиком,
# открытие треда (MB10READ) голосовое не красит — синие ✓✓ только после прослушивания (MB10LISTEN), выключенные отчёты ничего автору не шлют, офлайн-получатель получает
# голосовое из очереди (в очереди ссылка без звука) ровно один раз. Запись микрофоном на эмуляторе не проверяется — звук подменяет отладочная команда sayvoice (случайные байты).
source "$(dirname "$0")/../lib.sh"
echo "== voice"
PKA=$(cat "$E2E_DIR/pk_$A.txt"); PKB=$(cat "$E2E_DIR/pk_$B.txt")
# Голосовые отправителя по порядку отправки (0 — самое раннее): статус MessageStatus (1 ждёт, 2 ушло, 3 доставлено, 5 прослушано).
vstatus() { q $A "select status from chat_messages where body like 'MB10VM:%' order by timestamp asc limit 1 offset $1"; }
vrows() { q $B "select count(*) from chat_messages where body like 'MB10VM:%'"; }
# Файлы звука у получателя: сколько и самый большой (байт).
vls() { adb_ $B shell "run-as $PKG ls -l files/voice 2>/dev/null" | tr -d '\r'; }
vfiles() { vls | awk 'NF>=8{n++} END{print n+0}'; }
vbiggest() { vls | awk 'NF>=8 && $5>m{m=$5} END{print m+0}'; }
listen() { adb_ $B logcat -c; dbg $B DEBUG_SET --es listenvoice "$PKA"; await 15 bash -c "source '$ROOT/scripts/e2e/lib.sh'; adb_ $B logcat -d -s MB10DBG | grep 'listenvoice ->' | tail -1 | sed 's/.*-> //'"; }
readthread() { adb_ $B logcat -c; dbg $B DEBUG_SET --es readthread "$PKA"; await 15 bash -c "source '$ROOT/scripts/e2e/lib.sh'; adb_ $B logcat -d -s MB10DBG | grep 'readthread ->' | tail -1 | sed 's/.*-> //'"; }
# Обрыв и возврат получателя — как в network-drop: проброс порта Боба снимаем и гасим Wi-Fi, потом связываем заново.
drop() { adb_ $B emu redir del tcp:24817 >/dev/null 2>&1; adb_ $B shell svc wifi disable; }
restore() { adb_ $B shell svc wifi enable; sleep 6; "$ROOT/scripts/e2e/link.sh" >/dev/null 2>&1; }
dbg $B DEBUG_SET --es readreceipts on

# 1. Короткое: доходит, файл у получателя, у отправителя «доставлено».
dbg $A DEBUG_SET --es sayvoice "$PKB|5"
eq_wait 30 "1: у отправителя «доставлено» — получатель сохранил файл" 3 vstatus 0
eq_wait 15 "1: у получателя ровно одно голосовое в треде" 1 vrows
eq "1: у получателя один файл звука" 1 "$(vfiles)"

# 2. Предельное: 60 с ≈ 150 КБ одной строкой.
dbg $A DEBUG_SET --es sayvoice "$PKB|60"
eq_wait 90 "2: 60-секундное «доставлено»" 3 vstatus 1
eq_wait 15 "2: у получателя два голосовых" 2 vrows
check "2: файл ≥ 140 КБ дошёл целиком" test "$(vbiggest)" -ge 140000

# 3. Открытие треда не красит голосовые: отчёт «прочитано» доходит до текста, голосовые остаются «доставлено».
T="e2e-voice-text-$RANDOM"
dbg $A DEBUG_SET --es say "$PKB|$T"
eq_wait 30 "3: текст доставлен" 3 q $A "select status from chat_messages where body = '$T'"
eq "3: получатель открыл тред — отчёт ушёл" "SENT" "$(readthread)"
eq_wait 30 "3: у текста «прочитано»" 4 q $A "select status from chat_messages where body = '$T'"
eq "3: голосовое не стало «прочитано»" 3 "$(vstatus 0)"
eq "3: 60-секундное тоже" 3 "$(vstatus 1)"

# 4. Прослушивание: самое раннее непрослушанное, у отправителя синие ✓✓ (5), второе остаётся «доставлено», потом второе, потом NONE.
check "4: получатель запустил первое голосовое" test "$(listen)" != NONE
eq_wait 30 "4: у отправителя первое «прослушано»" 5 vstatus 0
eq "4: второе ещё «доставлено»" 3 "$(vstatus 1)"
check "4: у получателя первое помечено прослушанным (точка погасла)" test "$(q $B "select count(*) from chat_messages where body like 'MB10VM:%' and status = 5")" = 1
check "4: следующее запущено" test "$(listen)" != NONE
eq_wait 30 "4: у отправителя второе «прослушано»" 5 vstatus 1
eq "4: непрослушанных больше нет" "NONE" "$(listen)"

# 5. Выключенные отчёты: «прослушано» у себя есть, автору ничего не уходит.
dbg $B DEBUG_SET --es readreceipts off
dbg $A DEBUG_SET --es sayvoice "$PKB|3"
eq_wait 30 "5: третье «доставлено»" 3 vstatus 2
check "5: получатель запустил третье" test "$(listen)" != NONE
eq "5: у получателя третье помечено прослушанным" 3 "$(q $B "select count(*) from chat_messages where body like 'MB10VM:%' and status = 5")"
sleep 12; eq "5: отправителю отчёт не пришёл" 3 "$(vstatus 2)"
dbg $B DEBUG_SET --es readreceipts on

# 6. Получатель офлайн: в очереди ссылка без звука, после возвращения — ровно одно сообщение, «доставлено».
drop; sleep 4
dbg $A DEBUG_SET --es sayvoice "$PKB|4"
check "6: голосовое встало в очередь у отправителя" wait_until 20 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(q $A 'select count(*) from outbox')\" -ge 1 ]"
eq "6: у отправителя «ждёт» (1)" 1 "$(vstatus 3)"
check "6: в очереди ссылка, а не звук (строка короче 1000 символов)" test "$(q $A 'select max(length(wireLine)) from outbox')" -lt 1000
eq "6: у получателя пока три голосовых" 3 "$(vrows)"
restore
eq_wait 120 "6: после возврата сети голосовое доехало само" 4 vrows
eq_wait 60 "6: очередь у отправителя опустела" 0 q $A "select count(*) from outbox"
eq_wait 30 "6: у отправителя «доставлено»" 3 vstatus 3
sleep 3; eq "6: ровно четыре голосовых, без дублей" 4 "$(vrows)"
eq "6: четыре файла звука" 4 "$(vfiles)"
finish
