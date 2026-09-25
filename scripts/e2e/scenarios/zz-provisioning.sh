#!/bin/bash
# Первый запуск по QR персонажа от мастера (docs/provisioning-qr.md): один код настраивает сервер и код игры и создаёт персонажа со стартовым
# балансом и RAM; код действует один раз; повторно — только после сброса сессии и с новым кодом.
# Сброс сессии стирает игровые данные устройства (docs/character-reissue.md), а не только ключи.
# РАЗРУШАЕТ состояние Alice (эмулятор A: стирает данные приложения) — поэтому идёт последним (zz-) и после него стенд надо поднимать заново.
source "$(dirname "$0")/../lib.sh"
echo "== provisioning"
# prov <номер> <позывной> <фракция> <баланс> <RAM> — строка QR персонажа (как её печатает Мастерская)
prov() {
  python3 - "$1" "$2" "$3" "$4" "$5" "$COLLECTOR_FROM_EMU" "${E2E_GAME_SECRET:-}" <<'PY'
import sys,base64
pid,cs,fac,bal,ram,url,secret=sys.argv[1:8]
b=lambda t: base64.b64encode(t.encode()).decode()
print(f"MB10:PROV:v1:{pid}:{b(url)}:{b(secret)}:{b(cs)}:{b(fac)}:{bal}:{ram}")
PY
}
identity_has() { adb_ $A exec-out run-as $PKG cat shared_prefs/identity_prefs.xml 2>/dev/null | grep -q "$1"; }
setup_screen() { screen_has $A "Сканировать QR персонажа"; }

# Особенность эмулятора: приложение, привязанное к виртуальному Wi-Fi, не достукивается до хоста (10.0.2.2) — см. seed.sh. На реальной сети такого нет.
adb_ $A shell svc wifi disable; sleep 3
# Чистая установка. pm clear убивает процесс, но процесс прежней сессии с foreground-сервисом (MeshForegroundService) может ещё доживать —
# тогда новый запуск откладывается на десятки секунд («refused to die», см. up.sh): экран выдачи появлялся через минуту с лишним, первый QR
# уходил в пустоту (DebugQrBus не хранит строку, пока экран её не слушает), и дальше сценарий валился каскадом. Поэтому: ждём, пока старый
# процесс уйдёт; разрешения выдаём ДО запуска (иначе поверх экрана выдачи висит системный запрос уведомлений); медленный старт — ещё раз.
# Повтор не прячет падения: журнал крэшей очищается до запуска и проверяется после.
adb_ $A logcat -b crash -c >/dev/null 2>&1
adb_ $A shell pm clear $PKG >/dev/null
wait_until 20 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ -z \"\$(adb_ $A shell pidof $PKG | tr -d '\r')\" ]" \
  || log "$A: процесс прежней сессии не ушёл за 20 с ($(app_state $A))"
for p in POST_NOTIFICATIONS RECORD_AUDIO CAMERA; do adb_ $A shell pm grant $PKG android.permission.$p >/dev/null 2>&1; done
start_app $A >/dev/null 2>&1
wait_until 20 setup_screen || { log "$A: экрана выдачи нет через 20 с ($(app_state $A)) — запускаю ещё раз"; start_app $A >/dev/null 2>&1; }
check "первый запуск показывает выдачу персонажа по QR" wait_until 30 setup_screen
setup_screen || log "$A: экрана выдачи так и нет ($(app_state $A))"
eq "приложение не падало при первом запуске" 0 "$(adb_ $A logcat -b crash -d 2>/dev/null | grep -c "Process: $PKG")"

# 1. QR, выданный самим сервером (POST /api/provisions, как форма «Персонаж» в Мастерской): проверка, что кодек Kotlin читает то, что пишет кодек TypeScript
ISSUED=$(api POST /api/provisions '{"callsign":"Prov","faction":"Neon","balance":300,"ram":8}')
PID1=$(echo "$ISSUED" | jq_ 'd["item"]["id"]'); QR1=$(echo "$ISSUED" | jq_ 'd["qr"]')
[ -n "$QR1" ] || die "сервер не выдал QR персонажа"
check "в QR сервера есть адрес (PUBLIC_URL стенда)" bash -c "echo '$QR1' | python3 -c \"import sys,base64;p=sys.stdin.read().strip().split(':');assert base64.b64decode(p[4]).decode().startswith('http')\""
dbg $A DEBUG_QR --es qr "$QR1"
check "персонаж создан из QR (позывной Prov)" wait_until 30 identity_has 'Prov'
check "ёмкость буфера из QR (8)" wait_until 15 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(ram_of $A)\" = 8 ]"
check "на дашборде: Prov, Neon, баланс 300, RAM 8" wait_until 90 bash -c "source '$ROOT/scripts/e2e/lib.sh'; api GET /api/players | jq_ 'any(p[\"callsign\"]==\"Prov\" and p[\"faction\"]==\"Neon\" and p[\"balance\"]==300 and p[\"ramCapacity\"]==8 for p in d)' | grep -q True"

# 2. персонаж уже есть: другой код не применяется
dbg $A DEBUG_QR --es qr "$(prov e2e-prov-2 Intruder Rats 999 13)"; sleep 4
check "чужой код не заменил персонажа" bash -c "source '$ROOT/scripts/e2e/lib.sh'; ! adb_ $A exec-out run-as $PKG cat shared_prefs/identity_prefs.xml | grep -q Intruder"

# 3. сброс сессии стирает игровые данные устройства; тот же код второй раз не принимается, новый — принимается
PKB=$(cat "$E2E_DIR/pk_$B.txt")
dbg $A DEBUG_SET --es daemon "Остаток:1C,FF:2:MINER"; dbg $A DEBUG_SET --es contact "$PKB:Bob:Rats"; sleep 2
eq "до сброса: демон, контакт и стартовый баланс на месте" "1|1|300" "$(q $A "select (select count(*) from daemons)||'|'||(select count(*) from characters)||'|'||(select coalesce(sum(amount),0) from transactions)")"
dbg $A DEBUG_SET --es sessionreset 1; sleep 2
eq "после сброса игровые данные стёрты (демоны, контакты, кошелёк)" "0|0|0" "$(q $A "select (select count(*) from daemons)||'|'||(select count(*) from characters)||'|'||(select coalesce(sum(amount),0) from transactions)")"
restart_app $A >/dev/null 2>&1; sleep 3
check "после сброса снова экран выдачи" wait_until 30 setup_screen
dbg $A DEBUG_QR --es qr "$QR1"; sleep 5
check "использованный код не принят повторно" setup_screen
check "личность не создалась" bash -c "source '$ROOT/scripts/e2e/lib.sh'; ! adb_ $A exec-out run-as $PKG cat shared_prefs/identity_prefs.xml | grep -q 'public_key'"
dbg $A DEBUG_QR --es qr "$(prov e2e-prov-3 Prov2 Neon 100 6)"
check "новый код от мастера принят" wait_until 30 identity_has 'Prov2'
# Личность (prefs) появляется раньше, чем коммитится транзакция с записями и стартовым балансом, — баланс ждём. Остатки прежнего дали бы не 100 насовсем.
check "баланс нового персонажа ровно из QR, без остатков прежнего" wait_until 15 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(q $A 'select coalesce(sum(amount),0) from transactions')\" = 100 ]"
q $A 'select coalesce(sum(amount),0) from transactions' | grep -qx 100 || log "$A: баланс нового персонажа — $(q $A 'select coalesce(sum(amount),0) from transactions')"
eq "у нового персонажа нет ни остатков демонов, ни чужих контактов" "0|0" "$(q $A "select (select count(*) from daemons)||'|'||(select count(*) from characters)")"

# 4. сервер отказал в коде (его уже применил другой телефон): приложение объясняет игроку и не зацикливает синхронизацию
check "сервер запомнил применение кода первым телефоном" wait_until 60 bash -c "source '$ROOT/scripts/e2e/lib.sh'; api GET /api/provisions | jq_ 'any(i[\"id\"]==\"$PID1\" and i[\"boundKey\"] for i in d[\"items\"])' | grep -q True"
dbg $A DEBUG_SET --es sessionreset 1; sleep 2; restart_app $A >/dev/null 2>&1; sleep 3
check "снова экран выдачи" wait_until 30 setup_screen
SQ=$(api POST /api/provisions '{"callsign":"Squatted","faction":"Rats","balance":50,"ram":6}')
SID=$(echo "$SQ" | jq_ 'd["item"]["id"]'); SQR=$(echo "$SQ" | jq_ 'd["qr"]')
NODE=${NODE_BIN:+$NODE_BIN/}node
"$NODE" "$ROOT/scripts/e2e/fakedev.mjs" --api "$API" --dir "$E2E_DIR/fake" --secret "${E2E_GAME_SECRET:-none}" register Squatter --provision "$SID" >/dev/null   # чужой телефон применил код раньше
dbg $A DEBUG_QR --es qr "$SQR"
check "приложение запомнило отказ по коду (плашка в Настройках)" wait_until 90 bash -c "source '$ROOT/scripts/e2e/lib.sh'; adb_ $A exec-out run-as $PKG cat shared_prefs/collector_prefs.xml | grep -q 'provision_rejected\" value=\"true'"
eq "игрока с чужим кодом на дашборде нет" 0 "$(api GET /api/players | jq_ 'sum(1 for p in d if p["callsign"]=="Squatted")')"
check "на дашборде тревога provision_conflict" bash -c "source '$ROOT/scripts/e2e/lib.sh'; api GET /api/attention | jq_ 'any(i[\"kind\"]==\"provision_conflict\" for i in d[\"items\"])' | grep -q True"
ensure_wifi_on $A   # вернуть Wi-Fi: выключенный остаётся выключенным и на следующем стенде
finish
