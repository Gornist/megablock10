#!/bin/bash
# Gradle на devbox одной командой: синхронизация рабочей копии через git, очередь (flock), отвязанный запуск, один итог.
#   scripts/dbx.sh [-n имя] --auto        — задачи по изменённым путям (детект всегда; kit/ → kit-тесты и Animal Sniffer; app/ → unit-тесты;
#                                           ui/, скриншоты, сборка → verifyPaparazziDebug; только документы — пропуск)
#   scripts/dbx.sh [-n имя] --full        — всё: kit-тесты, detekt, Animal Sniffer, Android Lint, verifyPaparazziDebug (перед PR)
#   scripts/dbx.sh [-n имя] -- <аргументы gradlew…>   — свои задачи (например `-- :app:testDebugUnitTestNoScreenshots --tests '*XTest*'`)
# Имя — постоянная папка ~/wt-dbx-<имя> на devbox (по умолчанию — имя ветки): кэши тёплые между запусками. Версия на проверке = коммит из
# рабочего дерева (включая незакоммиченное и новые файлы), в итоге печатается его sha.
# Блокировку держит сам процесс на devbox (~/.dbx.lock): параллельные вызовы встают в очередь, обрыв ssh её не снимает.
# Вызывать один раз и ждать итога (минуты): опрос внутри скрипта, не более ≈90 мин. Из агента — обычным вызовом Bash, без собственного опроса.
# ./gradlew --stop на devbox не вызываем: демон общий с другими сессиями (skill devbox).
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2
NAME=$(git rev-parse --abbrev-ref HEAD | tr '/ ' '--'); MODE=""; ARGS=""
while [ $# -gt 0 ]; do case $1 in
  -n) NAME=$2; shift 2;;
  --auto) MODE=auto; shift;;
  --full) MODE=full; shift;;
  --) shift; MODE=custom; ARGS="$*"; break;;
  *) echo "неизвестный аргумент: $1"; sed -n 2,7p "$0"; exit 2;;
esac; done
[ -n "$MODE" ] || { sed -n 2,7p "$0"; exit 2; }

# Коммит текущего дерева (включая незакоммиченное и новые файлы) во временном индексе — рабочая копия и индекс не меняются.
T=$(mktemp -u); trap 'rm -f "$T"' EXIT
GIT_INDEX_FILE=$T git read-tree HEAD && GIT_INDEX_FILE=$T git add -A || { echo "не собрал временный индекс"; exit 2; }
C=$(git commit-tree "$(GIT_INDEX_FILE=$T git write-tree)" -p HEAD -m "dbx $NAME") || exit 2
git push -q devbox "+$C:refs/dbx/$NAME" --no-verify 2>&1 | tail -3
OK="$(git rev-parse --git-common-dir)/dbx-ok-$NAME"   # последний зелёный --auto/--full (синтетический коммит дерева)
FULL=":kit:test :app:detekt :kit:detekt :kit:animalsnifferMain :app:lintDebug verifyPaparazziDebug"
if [ $MODE = full ]; then ARGS=$FULL
elif [ $MODE = auto ]; then
  BASE=$(cat "$OK" 2>/dev/null); git cat-file -e "${BASE:-x}^{commit}" 2>/dev/null || BASE=$(git merge-base origin/main HEAD)
  CH=$(git diff --name-only "$BASE" "$C" 2>/dev/null | sort -u)
  if echo "$CH" | grep -qE '^(build\.gradle|settings\.gradle|gradle\.properties|gradle/|app/build\.gradle|kit/build\.gradle|rules/build\.gradle)'; then ARGS=$FULL
  elif ! echo "$CH" | grep -qE '^(app|kit|rules)/'; then echo "DBX пропущен: с последнего зелёного прогона нет изменений в app/, kit/, rules/ и файлах сборки"; echo "$C" > "$OK"; exit 0
  else
    ARGS=":app:detekt :kit:detekt"
    echo "$CH" | grep -q '^kit/' && ARGS="$ARGS :kit:test :kit:animalsnifferMain"
    if echo "$CH" | grep -qE '^app/src/main/.*/ui/|^app/src/test/.*(screenshots|snapshots)'; then ARGS="$ARGS verifyPaparazziDebug"
    elif echo "$CH" | grep -q '^app/'; then ARGS="$ARGS :app:testDebugUnitTestNoScreenshots"; fi
  fi
fi

[ "${DBX_DRY:-}" = 1 ] && { echo "DBX dry: $ARGS"; exit 0; }

SSH="ssh -o ConnectTimeout=15 -o BatchMode=yes devbox"
JOB="dbx-$NAME-$(date +%s)"

# Исполнитель на devbox: очередь flock (fd 9 не отдаём Gradle: иначе демон удержит блокировку), отметки [dbx] для ожидающего.
$SSH 'cat > ~/.local/bin/dbx-run && chmod +x ~/.local/bin/dbx-run' <<'RUNNER'
#!/bin/bash
NAME=$1; C=$2; JOB=$3; D=$HOME/wt-dbx-$NAME
read -ra ARGS < "$HOME/jobs/$JOB.args"
echo "[dbx] queued $(date +%s)"
exec 9>"$HOME/.dbx.lock"
flock -w 2700 9 || { echo "[dbx] queue-timeout"; echo "[dbx] rc=3"; exit 3; }
echo "[dbx] start $(date +%s)"
if [ ! -d "$D" ]; then git -C "$HOME/megablock10" worktree add -q --detach "$D" "$C" && cp "$HOME/mb-main/local.properties" "$D/"; fi
git -C "$D" checkout -q -f --detach "$C" || { echo "[dbx] rc=4"; exit 4; }
export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64 PATH=/usr/lib/jvm/temurin-21-jdk-amd64/bin:$PATH
cd "$D" && ./gradlew --console=plain "${ARGS[@]}" 9>&-
echo "[dbx] rc=$? $(date +%s)"
RUNNER
echo "$ARGS" | $SSH "cat > ~/jobs/$JOB.args"
$SSH "~/.local/bin/devjob start $JOB 'dbx-run $NAME $C $JOB'" >/dev/null 2>&1 || { echo "не запустил задачу на devbox"; exit 2; }

START=$(date +%s); RC=""; TAIL=""
for i in $(seq 1 360); do
  sleep 15
  TAIL=$($SSH "grep -E '^\[dbx\]' ~/jobs/$JOB.log 2>/dev/null; ~/.local/bin/devjob status $JOB" 2>/dev/null) || continue
  RC=$(echo "$TAIL" | sed -n 's/^\[dbx\] rc=\([0-9]*\).*/\1/p' | tail -1)
  [ -n "$RC" ] && break
  echo "$TAIL" | grep -q "завершена\|нет такой" && { RC=9; break; }
done
[ -n "$RC" ] || RC=8
Q=$(echo "$TAIL" | sed -n 's/^\[dbx\] queued \([0-9]*\)/\1/p' | tail -1); S=$(echo "$TAIL" | sed -n 's/^\[dbx\] start \([0-9]*\)/\1/p' | tail -1)
E=$(echo "$TAIL" | sed -n 's/^\[dbx\] rc=[0-9]* \([0-9]*\)/\1/p' | tail -1)
echo "DBX rc=$RC commit=${C:0:7} name=$NAME очередь=$(( ${S:-0} > 0 && ${Q:-0} > 0 ? S-Q : 0 ))с сборка=$(( ${E:-0} > 0 && ${S:-0} > 0 ? E-S : $(date +%s)-START ))с задачи: $ARGS"
[ "$RC" = 0 ] && { [ $MODE != custom ] && echo "$C" > "$OK"; $SSH "grep -E 'тестов [0-9]+|BUILD SUCCESSFUL' ~/jobs/$JOB.log | tail -4" 2>/dev/null; exit 0; }
$SSH "grep -nE 'FAILED|BUILD FAILED|^e: |Lint found|What went wrong|Failed to|тестов [0-9]+, .*упало [1-9]|Exception' ~/jobs/$JOB.log | head -40; echo '--- хвост ---'; tail -n 15 ~/jobs/$JOB.log" 2>/dev/null
echo "полный журнал: ssh devbox 'cat ~/jobs/$JOB.log'"
exit "$RC"
