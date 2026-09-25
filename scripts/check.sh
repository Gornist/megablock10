#!/bin/bash
# Единая локальная проверка перед пушем — то же, что делает CI, плюс (по флагу) e2e. Каждый шаг пишет лог в /tmp/mb10-check/, в конце — время шагов.
#   scripts/check.sh --fast     — pre-push хук (≤ 1 мин): detekt, Animal Sniffer, Android Lint, :kit:test, тесты сервера — по изменённым путям;
#                                 без Robolectric/Paparazzi (все тесты приложения и скриншоты — CI и --all). docs/refactor-plan.md, A5
#   scripts/check.sh            — юнит- и скриншот-тесты приложения (если менялось app/) + тесты сервера + сборка/линт клиента (если менялся admin-web/)
#   scripts/check.sh --all      — то же без пропусков «ничего не менялось»
#   scripts/check.sh --e2e      — плюс поднять стенд (up.sh --no-build) и прогнать все сценарии
# Что «менялось» считается относительно origin/main (незапушенные коммиты + рабочее дерево).
cd "$(dirname "$0")/.." || exit 1
ROOT=$PWD; LOGS=/tmp/mb10-check; mkdir -p $LOGS
export JAVA_HOME=${JAVA_HOME:-/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home}
# Кодировка вывода клиента Gradle берётся из локали (stdout.encoding): при пустом LANG (облачная сессия, cron) русский текст — «???».
[ "$(locale charmap 2>/dev/null)" = UTF-8 ] || export LC_ALL=C.UTF-8
# Node для сервера/клиента: LTS 22 (зависимости сервера требуют >=22), запасной — 20; NODE_BIN переопределяет. На CI node берётся из setup-node.
for d in "${NODE_BIN:-}" /opt/homebrew/opt/node@22/bin /opt/homebrew/opt/node@20/bin; do [ -n "$d" ] && [ -d "$d" ] && { NODE_BIN=$d; break; }; done
export PATH="${NODE_BIN:+$NODE_BIN:}$PATH"
ALL=0; E2E=0; FAST=0; for a in "$@"; do case $a in --all) ALL=1;; --e2e) E2E=1; ALL=1;; --fast) FAST=1;; esac; done
changed() { [ $ALL -eq 1 ] || { git diff --name-only origin/main 2>/dev/null; git ls-files --others --exclude-standard; } | grep -q "^$1"; }
declare -a TIMES; FAIL=0
step() { # step "имя" команда...
  local name=$1; shift; local t0=$(date +%s) log="$LOGS/${name// /_}.log"
  if "$@" > "$log" 2>&1; then r="ок"
  else r="ПРОВАЛ (см. $log)"; FAIL=1; fi
  TIMES+=("$name: $r, $(( $(date +%s) - t0 )) с")
}
skip() { TIMES+=("$1: пропущено (нет изменений)"); }

# kit/ — часть приложения (подключён к :app), поэтому любая его правка тоже гоняет проверки приложения.
if changed app || changed kit; then
  step "app+kit: detekt" ./gradlew -q --console=plain :app:detekt :kit:detekt   # статический анализ; старые находки в app/detekt-baseline.xml, новые ломают проверку
  step "kit: API Android 8.0" ./gradlew -q --console=plain :kit:animalsnifferMain   # kit собирается JDK 17+, но работает на Android 26: вызов более нового API ломает проверку
  step "app: Android Lint" ./gradlew -q --console=plain :app:lintDebug   # полный набор (включая NewApi — API новее Android 8.0); baseline app/lint-baseline.xml
  step "kit: unit-тесты" ./gradlew -q --console=plain :kit:test
  # verifyPaparazziDebug прогоняет ВСЕ unit-тесты приложения: скриншоты (testDebugUnitTest) и остальное (testDebugUnitTestNoScreenshots)
  # — в разных JVM, каждый тест один раз. Эталоны: app/src/test/snapshots; обновить: ./gradlew recordPaparazziDebug
  # Не cleanTestDebugUnitTest: Paparazzi считает эталоны выходом задачи, и clean их удаляет (заново без кэша — --rerun-tasks).
  if [ $FAST -eq 1 ]; then TIMES+=("app: unit- и скриншот-тесты: не в хуке (CI; вручную — scripts/check.sh --all)")
  else step "app: unit- и скриншот-тесты" ./gradlew -q --console=plain verifyPaparazziDebug; fi
else skip "app: unit- и скриншот-тесты"; fi
if changed admin-web/server; then step "server: тесты" bash -c 'cd admin-web/server && npm test --silent'; else skip "server: тесты"; fi
if [ $FAST -eq 1 ]; then TIMES+=("admin-web: сборка: не в хуке (CI)")
elif changed admin-web; then
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
