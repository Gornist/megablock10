#!/bin/bash
# Пропал со связи: настоящий эмулятор Bob шлёт heartbeat на отдельный сервер, затем уходит в авиарежим → went_silent (порог на стенде 45 с, heartbeat телефона раз в 30 с).
# Нужен поднятый основной стенд (up.sh); без эмуляторов сценарий пропускается.
source "$(dirname "$0")/../anom-lib.sh"
MAIN=/tmp/mb10-e2e
if ! adb_ $B shell true >/dev/null 2>&1 || [ ! -f "$MAIN/pk_$A.txt" ]; then echo "== anomaly-silent-phone (пропущен: нет эмуляторов, сначала ./up.sh)"; exit 0; fi
echo "== anomaly-silent-phone"
PKA=$(cat "$MAIN/pk_$A.txt")
anom_up ATTN_SILENT_MIN=0.75 ATTN_SILENT_MAX_MIN=60
restore() { adb_ $B shell cmd connectivity airplane-mode disable >/dev/null 2>&1; dbg $B DEBUG_SET --es collector "http://10.0.2.2:2517" >/dev/null 2>&1; server_stop; }
trap restore EXIT
dbg $B DEBUG_SET --es collector "http://10.0.2.2:$PORT"
dbg $B DEBUG_SET --es balance 100; dbg $B DEBUG_SET --es pay "$PKA:1:offline"
# на новом сервере у Bob нет записи о создании персонажа (она ушла на основной), так что позывного нет — считаем просто игроков
seen() { [ "$(api GET /api/players | jq_ 'len(d)')" -ge 1 ]; }
if ! wait_until 75 seen; then adb_ $B shell svc wifi disable; wait_until 90 seen || die "телефон Bob не дошёл до сервера сценария"; fi
echo "  (телефон на связи)"
sleep 40
expect_no_kind went_silent "телефон шлёт heartbeat каждые 30 с — молчания нет"
adb_ $B shell cmd connectivity airplane-mode enable >/dev/null 2>&1
expect_kind went_silent 90
adb_ $B shell cmd connectivity airplane-mode disable >/dev/null 2>&1
anom_finish
