#!/bin/bash
# Единая локальная проверка перед пушем — то же, что делает CI, плюс (по флагу) e2e. Каждый шаг пишет лог в /tmp/mb10-check/, в конце — время шагов.
#   scripts/check.sh            — быстрая: юнит-тесты приложения (если менялось app/) + тесты сервера + сборка/линт клиента (если менялся admin-web/)
#   scripts/check.sh --all      — то же без пропусков «ничего не менялось»
#   scripts/check.sh --e2e      — плюс поднять стенд (up.sh --no-build) и прогнать все сценарии
# Что «менялось» считается относительно origin/main (незапушенные коммиты + рабочее дерево).
cd "$(dirname "$0")/.." || exit 1
ROOT=$PWD; LOGS=/tmp/mb10-check; mkdir -p $LOGS
export JAVA_HOME=${JAVA_HOME:-/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home}
# Node для сервера/клиента: LTS 22 (зависимости сервера требуют >=22), запасной — 20; NODE_BIN переопределяет. На CI node берётся из setup-node.
for d in "${NODE_BIN:-}" /opt/homebrew/opt/node@22/bin /opt/homebrew/opt/node@20/bin; do [ -n "$d" ] && [ -d "$d" ] && { NODE_BIN=$d; break; }; done
export PATH="${NODE_BIN:+$NODE_BIN:}$PATH"
ALL=0; E2E=0; for a in "$@"; do case $a in --all) ALL=1;; --e2e) E2E=1; ALL=1;; esac; done
changed() { [ $ALL -eq 1 ] || { git diff --name-only origin/main 2>/dev/null; git ls-files --others --exclude-standard; } | grep -q "^$1"; }
declare -a TIMES; FAIL=0
step() { # step "имя" команда...
  local name=$1; shift; local t0=$(date +%s)
  if "$@" > "$LOGS/${name// /_}.log" 2>&1; then r="ок"; else r="ПРОВАЛ (см. $LOGS/${name// /_}.log)"; FAIL=1; fi
  TIMES+=("$name: $r, $(( $(date +%s) - t0 )) с")
}
skip() { TIMES+=("$1: пропущено (нет изменений)"); }

if changed app; then
  step "app: detekt" ./gradlew -q --console=plain :app:detekt   # статический анализ; старые находки в app/detekt-baseline.xml, новые ломают проверку
  step "app: unit-тесты" ./gradlew -q --console=plain testDebugUnitTest
  step "app: скриншот-тесты" ./gradlew -q --console=plain verifyPaparazziDebug   # эталоны: app/src/test/snapshots; обновить: ./gradlew recordPaparazziDebug
else skip "app: unit- и скриншот-тесты"; fi
if changed admin-web/server; then step "server: тесты" bash -c 'cd admin-web/server && npm test --silent'; else skip "server: тесты"; fi
if changed admin-web; then
  step "server: сборка" bash -c 'cd admin-web/server && npm run build --silent'
  step "client: тесты, линт и сборка" bash -c 'cd admin-web/client && npm test --silent && npm run lint --silent && npm run build --silent'
else skip "admin-web: сборка"; fi
if [ $E2E -eq 1 ] && [ $FAIL -eq 0 ]; then
  step "e2e: сборка APK" ./gradlew -q --console=plain assembleDebug
  step "e2e: стенд" scripts/e2e/up.sh --no-build
  step "e2e: сценарии" scripts/e2e/run-all.sh
fi
echo "── check:"; printf '  %s\n' "${TIMES[@]}"
[ $FAIL -eq 0 ] && echo "ВСЁ ЗЕЛЁНОЕ" || echo "ЕСТЬ ПРОВАЛЫ"
exit $FAIL
