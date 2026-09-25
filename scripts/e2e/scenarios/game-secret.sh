#!/bin/bash
# Код игры (GAME_SECRET): сервер отклоняет телефон с неверным кодом (записи копятся в очереди, не теряются), а после исправления кода доставляет всё.
# Работает только на стенде с кодом: E2E_GAME_SECRET=строка ./up.sh — иначе пропускается.
source "$(dirname "$0")/../lib.sh"
if [ -z "${E2E_GAME_SECRET:-}" ]; then echo "== game-secret (пропущен: стенд без E2E_GAME_SECRET)"; exit 0; fi
echo "== game-secret"
PKB=$(cat "$E2E_DIR/pk_$B.txt")
dbg $A DEBUG_SET --es balance 200
eq_wait 15 "баланс для перевода" 200 bal_of $A

# 1. телефон с неверным кодом: перевод создан, но на дашборд не попадает, очередь не пустеет
dbg $A DEBUG_SET --es secret "wrong-secret-xyz"; sleep 1
adb_ $A logcat -c
dbg $A DEBUG_SET --es pay "$PKB:4:offline"
TX=$(await 15 tx_of $A); [ -n "$TX" ] || die "перевод не создан"
sleep 20
check "с неверным кодом запись не дошла до дашборда" bash -c "source '$ROOT/scripts/e2e/lib.sh'; api GET /api/transfers | jq_ 'any(t[\"txId\"]==\"$TX\" for t in d)' | grep -q False"
check "запись не потеряна: осталась в очереди" bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(q $A 'select count(*) from pending_change_records')\" -gt 0 ]"

# 2. код исправлен — то, что накопилось, доходит
dbg $A DEBUG_SET --es secret "$E2E_GAME_SECRET"; sleep 1
check "после исправления кода запись дошла" wait_until 150 bash -c "source '$ROOT/scripts/e2e/lib.sh'; api GET /api/transfers | jq_ 'any(t[\"txId\"]==\"$TX\" for t in d)' | grep -q True"
check "очередь опустела" wait_until 60 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(q $A 'select count(*) from pending_change_records')\" -eq 0 ]"
finish
