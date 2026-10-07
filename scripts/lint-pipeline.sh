#!/bin/bash
# Статическая проверка конвейера: shellcheck по скриптам, actionlint по workflows, тесты хука (scripts/test-hook.sh).
# Печатает одну строку: «LINT OK» или «LINT FAIL: shellcheck N, actionlint M, hook K» + путь к полному журналу. Код 0/1.
# Нет shellcheck/actionlint — «LINT НЕ ПРОВЕРЕНО: нет …», код 3.
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1
for tool in shellcheck actionlint jq; do
  command -v "$tool" >/dev/null || { echo "LINT НЕ ПРОВЕРЕНО: нет $tool"; exit 3; }
done
log="${TMPDIR:-/tmp}"
log="${log%/}/lint-pipeline.log"
: >"$log"

files=""
for f in check verify dbx ci-wait agent-worktree zone-check train land test-hook lint-pipeline; do
  files="$files scripts/$f.sh"
done
files="$files .claude/hooks/guard-bash.sh .claude/hooks/session-brief.sh"

{ echo "== shellcheck -S warning"; } >>"$log"
# shellcheck disable=SC2086  # список файлов без пробелов в именах — разбиение по словам намеренное
shellcheck -S warning $files >>"$log" 2>&1
sc=$?
sc_n=$(grep -c '^In .* line [0-9]*:' "$log")
[ "$sc" -ne 0 ] && [ "$sc_n" -eq 0 ] && sc_n=1

echo "== actionlint" >>"$log"
# Порог shellcheck внутри run: — как у скриптов (warning): иначе info-замечания зависят от версии shellcheck
# (06.10: на Mac чисто, на ubuntu-latest SC2015:info в firmware.yml ронял job).
al_out=$(SHELLCHECK_OPTS='-S warning' actionlint .github/workflows/*.yml 2>&1)
al=$?
printf '%s\n' "$al_out" >>"$log"
al_n=0
[ "$al" -ne 0 ] && al_n=$(printf '%s\n' "$al_out" | grep -c '^[^ ].*:[0-9]*:[0-9]*: ')
[ "$al" -ne 0 ] && [ "$al_n" -eq 0 ] && al_n=1

echo "== test-hook" >>"$log"
hk_out=$(scripts/test-hook.sh 2>&1)
hk=$?
printf '%s\n' "$hk_out" >>"$log"
hk_n=0
[ "$hk" -ne 0 ] && hk_n=$(printf '%s\n' "$hk_out" | grep -c '^HOOK FAIL')
[ "$hk" -ne 0 ] && [ "$hk_n" -eq 0 ] && hk_n=1

if [ "$sc" -eq 0 ] && [ "$al" -eq 0 ] && [ "$hk" -eq 0 ]; then
  echo "LINT OK"
  exit 0
fi
echo "LINT FAIL: shellcheck $sc_n, actionlint $al_n, hook $hk_n (журнал: $log)"
# В CI журнал — сразу в вывод шага: --log-failed показывает только упавший шаг, отдельный шаг «Журнал» туда не попадает.
[ -n "${GITHUB_ACTIONS:-}" ] && grep -vE '^(==|$)' "$log" | head -40
exit 1
