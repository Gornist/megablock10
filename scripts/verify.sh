#!/bin/bash
# Одна проверка для любой области: смотрит, что изменила ветка (коммиты от origin/main + рабочее дерево + новые файлы), и зовёт
# проверку своей области; каждая печатает свой короткий вердикт, в конце — одна строка VERIFY. Раньше агент сам выбирал набор и
# путался: полный Gradle или gdUnit на каждый шаг (17 полных прогонов gdUnit за сессию), а соседние области не проверял вовсе.
#   scripts/verify.sh            на шаг: по изменённому (Android — dbx.sh --auto, Godot — dev.sh test, коллектор — test.sh своей части)
#   scripts/verify.sh --full     перед PR: полные наборы затронутых областей (Godot --all — 5–10 мин: Bash с run_in_background)
#   scripts/verify.sh --dry      только показать, что запустится
# Области идут по очереди (Mac 8 ГБ, devbox — одна задача на машину). e2e — только в CI на PR (≈17 мин). Журналы — /tmp/mb10-verify/.
# Код 0 — всё зелёное (или нечего проверять), 1 — есть красное, 3 — часть не проверена (много наборов Godot: нужен --full).
cd "$(dirname "$0")/.." || exit 1
FULL=0; DRY=0
for a in "$@"; do case $a in --full) FULL=1;; --dry) DRY=1;; *) echo "неизвестный ключ: $a (есть --full, --dry)"; exit 2;; esac; done
LOGS=/tmp/mb10-verify; mkdir -p $LOGS
git fetch -q origin main 2>/dev/null || true
CH=$( { git diff --name-only origin/main...HEAD; git diff --name-only HEAD; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u)
hit() { grep -qE "$1" <<<"$CH"; }

NAMES=(); CMDS=()
add() { NAMES+=("$1"); CMDS+=("$2"); }
if hit '^(app|kit|rules)/|^(build|settings)\.gradle|^gradle\.properties|^gradle/'; then
  [ $FULL = 1 ] && add android "scripts/dbx.sh --full" || add android "scripts/dbx.sh --auto"
fi
hit '^netrun-bridge/' && add bridge "scripts/dbx.sh -- :netrun-bridge:detekt :netrun-bridge:test"
if hit '^netrun/'; then [ $FULL = 1 ] && add godot "netrun/tools/dev.sh test --all" || add godot "netrun/tools/dev.sh test"; fi
# Ассеты без .gd (модели, src/*.py, шейдеры): dev.sh test по ним ничего не находит и молчит — проверяем правила ассетов явно (сессия Blender, 05.10).
[ $FULL = 0 ] && hit '^netrun/assets/' && add assets "netrun/tools/dev.sh test assets_models_test"
# Коллектор в свежей worktree: node_modules нет (или ссылка на чужие) — сначала свои зависимости, иначе красное не по делу (Godot, 05.10).
DEPS='for m in server client; do [ -d admin-web/$m/node_modules ] && [ ! -L admin-web/$m/node_modules ] || { admin-web/tools/wt-deps.sh all >/dev/null || exit 1; break; }; done; '
if hit '^admin-web/'; then
  if [ $FULL = 1 ]; then add collector "${DEPS}admin-web/tools/test.sh all"
  else
    hit '^admin-web/server/' && add server "${DEPS}admin-web/tools/test.sh server"
    hit '^admin-web/client/' && add client "${DEPS}admin-web/tools/test.sh client"
  fi
fi
FW='set -o pipefail; B=firmware/display/build; cmake -S firmware/display -B $B -DCMAKE_BUILD_TYPE=RelWithDebInfo >/dev/null && cmake --build $B -j >/dev/null && ctest --test-dir $B --output-on-failure | grep -E "tests passed|tests failed|Failed|\*\*\*"'
NOTE=""; hit '^scripts/e2e/' && NOTE="e2e — только в CI на PR (≈17 мин)"
# Хост-сборка прошивки — под Linux (accept4, SOCK_CLOEXEC; на macOS не собирается, проверено 05.10): на Mac — CI firmware.yml.
if hit '^firmware/display/'; then
  [ "$(uname)" = Linux ] && add firmware "$FW" || NOTE="${NOTE:+$NOTE; }прошивка — хост-тесты только под Linux: CI firmware.yml или devbox"
fi

if [ ${#NAMES[@]} -eq 0 ]; then echo "VERIFY: нечего проверять — изменены только документы/скрипты вне областей${NOTE:+; $NOTE}"; exit 0; fi
if [ $DRY = 1 ]; then for i in "${!NAMES[@]}"; do echo "${NAMES[$i]}: ${CMDS[$i]}"; done; [ -n "$NOTE" ] && echo "$NOTE"; exit 0; fi

RC=0; SUM=""
for i in "${!NAMES[@]}"; do
  n=${NAMES[$i]}; t0=$(date +%s)
  bash -c "${CMDS[$i]}" > "$LOGS/$n.log" 2>&1; r=$?
  echo "── $n ($(( $(date +%s) - t0 )) с):"; tail -n 15 "$LOGS/$n.log" | sed 's/^/  /'
  # dev.sh при >12 затронутых наборах ничего не гоняет и выходит с 0 — это не «ок» (Godot, 05.10).
  if [ $r -eq 0 ] && grep -q 'используйте dev.sh test --all' "$LOGS/$n.log"; then SUM="$SUM $n:НЕ_ПРОВЕРЕНО"; [ $RC = 0 ] && RC=3; continue; fi
  [ $r -eq 0 ] && SUM="$SUM $n:ок" || { SUM="$SUM $n:КРАСНО"; RC=1; }
done
[ $RC = 3 ] && NOTE="${NOTE:+$NOTE; }НЕ_ПРОВЕРЕНО: затронуто много наборов — scripts/verify.sh --full в фоне"
echo "VERIFY rc=$RC$SUM${NOTE:+ — $NOTE} (журналы: $LOGS/)"
exit $RC
