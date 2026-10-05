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
export JAVA_HOME=${JAVA_HOME:-/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home}
# Кодировка вывода клиента Gradle берётся из локали (stdout.encoding): при пустом LANG (облачная сессия, cron) русский текст — «???».
[ "$(locale charmap 2>/dev/null)" = UTF-8 ] || export LC_ALL=C.UTF-8
# Node для сервера/клиента — не ниже 22: на 20 better-sqlite3 13 падает SIGSEGV, vitest 5 не стартует. Берётся первый подходящий из NODE_BIN,
# node@22, node@26, /opt/homebrew/bin, PATH. Раньше был тихий откат на node@20 — пуш падал на 259 тестах сервера (04.10); теперь нет подходящего — шаги
# admin-web падают с понятной причиной.
NODE_DIR=
for d in "${NODE_BIN:-}" /opt/homebrew/opt/node@22/bin /opt/homebrew/opt/node@26/bin /opt/homebrew/bin "$(dirname "$(command -v node 2>/dev/null || echo .)")"; do
  [ -n "$d" ] && [ -x "$d/node" ] && [ "$("$d/node" -p 'process.versions.node.split(".")[0]')" -ge 22 ] 2>/dev/null && { NODE_DIR=$d; break; }
done
export PATH="${NODE_DIR:+$NODE_DIR:}$PATH"
# npm_in server|client 'команда' — в admin-web/<часть> со своими зависимостями. Симлинк на node_modules основной копии (так делали старые worktree)
# собран под чужой package-lock и чужую версию Node (NODE_MODULE_VERSION) — заменяется настоящей установкой; основной копии это не касается.
npm_in() {
  [ -n "$NODE_DIR" ] || { echo "нужен Node >= 22: brew install node@22 или NODE_BIN=<каталог с node>"; return 1; }
  ( cd "admin-web/$1" || exit 1
    if [ -L node_modules ] || [ ! -d node_modules ]; then rm -f node_modules; npm ci --silent --no-audit --no-fund || exit 1; fi
    eval "$2" )
}
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
if { changed app || changed kit || changed rules; } && [ $FAST -eq 1 ] && [ "$(uname)" = Darwin ] && [ -z "${CHECK_LOCAL_GRADLE:-}" ]; then
  # Mac (8 ГБ): Gradle здесь не гоняем (CLAUDE.md) — пуш с Mac падал без JDK 21, а сессии пушили «через devbox» руками (05.10).
  # Те же проверки — на devbox через scripts/dbx.sh --auto (очередь, кэш: после verify.sh обычно секунды). devbox недоступен — проверит CI.
  if ssh -o BatchMode=yes -o ConnectTimeout=5 devbox true 2>/dev/null; then step "app+kit: devbox (dbx.sh --auto)" scripts/dbx.sh --auto
  else TIMES+=("app+kit: devbox недоступен — Gradle-проверки сделает CI"); fi
elif changed app || changed kit || changed rules; then
  step "app+kit: detekt" ./gradlew -q --console=plain :app:detekt :kit:detekt :rules:detekt   # статический анализ; старые находки в app/detekt-baseline.xml, новые ломают проверку
  step "kit: API Android 8.0" ./gradlew -q --console=plain :kit:animalsnifferMain :rules:animalsnifferMain   # kit собирается JDK 17+, но работает на Android 26: вызов более нового API ломает проверку
  step "app: Android Lint" ./gradlew -q --console=plain :app:lintDebug   # полный набор (включая NewApi — API новее Android 8.0); baseline app/lint-baseline.xml
  step "kit: unit-тесты" ./gradlew -q --console=plain :kit:test :rules:test
  # verifyPaparazziDebug прогоняет ВСЕ unit-тесты приложения: скриншоты (testDebugUnitTest) и остальное (testDebugUnitTestNoScreenshots)
  # — в разных JVM, каждый тест один раз. Эталоны: app/src/test/snapshots; обновить: ./gradlew recordPaparazziDebug
  # Не cleanTestDebugUnitTest: Paparazzi считает эталоны выходом задачи, и clean их удаляет (заново без кэша — --rerun-tasks).
  if [ $FAST -eq 1 ]; then TIMES+=("app: unit- и скриншот-тесты: не в хуке (CI; вручную — scripts/check.sh --all)")
  else step "app: unit- и скриншот-тесты" ./gradlew -q --console=plain verifyPaparazziDebug; fi
else skip "app: unit- и скриншот-тесты"; fi
if changed admin-web/server; then step "server: тесты" npm_in server 'npm test --silent'; else skip "server: тесты"; fi
if [ $FAST -eq 1 ]; then TIMES+=("admin-web: сборка: не в хуке (CI)")
elif changed admin-web; then
  step "server: сборка" npm_in server 'npm run build --silent'
  step "client: тесты, линт и сборка" npm_in client 'npm test --silent && npm run lint --silent && npm run build --silent'
else skip "admin-web: сборка"; fi
if [ $E2E -eq 1 ] && [ $FAIL -eq 0 ]; then
  step "e2e: сборка APK" ./gradlew -q --console=plain assembleDebug
  step "e2e: стенд" scripts/e2e/up.sh --no-build
  step "e2e: сценарии" scripts/e2e/run-all.sh
fi
echo "── check:"; printf '  %s\n' "${TIMES[@]}"
[ $FAIL -eq 0 ] && echo "ВСЁ ЗЕЛЁНОЕ" || echo "ЕСТЬ ПРОВАЛЫ"
exit $FAIL
