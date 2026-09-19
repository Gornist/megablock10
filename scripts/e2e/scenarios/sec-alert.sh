#!/bin/bash
# Сигнал СБ: Alice (Neon) вскрывает узел фракции Rats → у Bob приходит «Тревога!» от SEC//MB10, счётчик на дашборде растёт.
source "$(dirname "$0")/../lib.sh"
echo "== sec-alert"
ID=sec-$RANDOM
QR=$(container $ID "Узел Крыс" BASE Rats 1) || die "не создал контейнер"
BEFORE=$(api GET /api/overview | jq_ 'd["alerts"]["sent"]')
autosolve $A true
breach $A "$QR"
check "Bob получил сигнал СБ" wait_until 90 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(q $B \"select count(*) from chat_messages where fromCallsign='SEC//MB10'\")\" -ge 1 ]"
check "дашборд насчитал отправленный сигнал" wait_until 60 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(api GET /api/overview | jq_ 'd[\"alerts\"][\"sent\"]')\" -gt $BEFORE ]"
finish
