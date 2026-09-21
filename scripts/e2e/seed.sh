#!/bin/bash
# Насыщает поднятый стенд (./up.sh) тестовыми данными — быстро, без тапов по экрану (в отличие от demo.sh, который ещё и снимает ролик):
# Alice и Bob с деньгами, демонами, перепиской, двумя переводами (один сведён, второй ждёт вашего «Принять» на телефоне Alice),
# узел на дашборде, объявление мастера. Для показа интерфейсов и ручного тыканья. Повторный запуск на том же стенде даст дубли — поднимайте up.sh заново.
#   ./up.sh && ./seed.sh
source "$(dirname "$0")/lib.sh"
PKA=$(cat "$E2E_DIR/pk_$A.txt"); PKB=$(cat "$E2E_DIR/pk_$B.txt")
step() { log "▶ $*"; }

heal_host_reach 2   # см. lib.sh: особенность эмулятора с виртуальным Wi-Fi

step "деньги, RAM, демоны"
dbg $A DEBUG_SET --es balance 250; dbg $B DEBUG_SET --es balance 900; dbg $A DEBUG_SET --es ram 9
dbg $A DEBUG_SET --es daemon "Cipher Key:7A,E9:2:DECRYPT"
dbg $A DEBUG_SET --es daemon "Deep Miner:E9,FF:2:MINER"
dbg $A DEBUG_SET --es daemon "Data Siphon:1C,FF:2:EXTRACT_SHARD"
dbg $B DEBUG_SET --es daemon "Black Curtain:7A,BD:2:BLACKOUT"

step "переписка"
dbg $B DEBUG_SET --es say "$PKA|Слушай, Alice. Есть работа: узел «Арасака-404»."; sleep 1.5
dbg $A DEBUG_SET --es say "$PKB|Согласна. Что по оплате?"; sleep 1.5
dbg $B DEBUG_SET --es say "faction|Крысы, сбор у техэтажа в 21:40."; sleep 1.5
dbg $A DEBUG_SET --es say "faction|Неон на связи. Ждём указаний."; sleep 1.5

step "перевод Bob → Alice 100 €\$ (принят, сведён)"
adb_ $B logcat -c
dbg $B DEBUG_SET --es pay "$PKA:100:online"; sleep 4
CARD=$(adb_ $B logcat -d -s MB10DBG | grep -o 'paycard=.*' | tail -1 | cut -d= -f2- | tr -d '\r')
[ -n "$CARD" ] || die "карточка перевода не создана (Bob и Alice видят друг друга? ./link.sh)"
dbg $A DEBUG_SET --es recv "$CARD"; sleep 3

step "перевод Bob → Alice 40 €\$ (ждёт «Принять» на телефоне Alice)"
dbg $B DEBUG_SET --es pay "$PKA:40:online"; sleep 3

step "узел и объявление на дашборде"
container arasaka-404-seed "Арасака-404" HARD Arasaka 1 >/dev/null
api POST /api/announcements '{"text":"Внимание, всем игрокам: сбор у центрального узла через 10 минут.","all":true}' >/dev/null
sleep 6
echo
echo "Готово. Дашборд: $API (мастер E2E, токен в $E2E_DIR/master.txt)."
echo "Alice: 250+100 €\$, 3 демона, RAM 9; Bob: 900−100−40 €\$, демон Black Curtain."
echo "В чате Alice, тред с Bob, ждёт карточка на 40 €\$: нажмите «Принять» — и на дашборде появится ещё один сведённый перевод."
