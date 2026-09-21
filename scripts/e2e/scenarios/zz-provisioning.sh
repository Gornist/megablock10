#!/bin/bash
# Первый запуск по QR персонажа от мастера (docs/provisioning-qr.md): один код настраивает сервер и код игры и создаёт персонажа со стартовым
# балансом и RAM; код действует один раз; повторно — только после сброса сессии и с новым кодом.
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

adb_ $A shell pm clear $PKG >/dev/null; start_app $A >/dev/null 2>&1
adb_ $A shell pm grant $PKG android.permission.POST_NOTIFICATIONS >/dev/null 2>&1
check "первый запуск показывает выдачу персонажа по QR" wait_until 30 setup_screen

# 1. настоящий QR: персонаж, сервер, стартовый баланс и RAM
dbg $A DEBUG_QR --es qr "$(prov e2e-prov-1 Prov Neon 300 8)"
check "персонаж создан из QR (позывной Prov)" wait_until 30 identity_has 'Prov'
eq "ёмкость буфера из QR" 8 "$(ram_of $A)"
check "на дашборде: Prov, Neon, баланс 300, RAM 8" wait_until 90 bash -c "source '$ROOT/scripts/e2e/lib.sh'; api GET /api/players | jq_ 'any(p[\"callsign\"]==\"Prov\" and p[\"faction\"]==\"Neon\" and p[\"balance\"]==300 and p[\"ramCapacity\"]==8 for p in d)' | grep -q True"

# 2. персонаж уже есть: другой код не применяется
dbg $A DEBUG_QR --es qr "$(prov e2e-prov-2 Intruder Rats 999 13)"; sleep 4
check "чужой код не заменил персонажа" bash -c "source '$ROOT/scripts/e2e/lib.sh'; ! adb_ $A exec-out run-as $PKG cat shared_prefs/identity_prefs.xml | grep -q Intruder"

# 3. сброс сессии: тот же код второй раз не принимается, новый — принимается
dbg $A DEBUG_SET --es sessionreset 1; sleep 1
restart_app $A >/dev/null 2>&1; sleep 3
check "после сброса снова экран выдачи" wait_until 30 setup_screen
dbg $A DEBUG_QR --es qr "$(prov e2e-prov-1 Prov Neon 300 8)"; sleep 5
check "использованный код не принят повторно" setup_screen
check "личность не создалась" bash -c "source '$ROOT/scripts/e2e/lib.sh'; ! adb_ $A exec-out run-as $PKG cat shared_prefs/identity_prefs.xml | grep -q 'public_key'"
dbg $A DEBUG_QR --es qr "$(prov e2e-prov-3 Prov2 Neon 100 6)"
check "новый код от мастера принят" wait_until 30 identity_has 'Prov2'
finish
