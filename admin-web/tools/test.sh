#!/usr/bin/env bash
# Проверки коллектора с правильным Node и коротким вердиктом вместо лога.
#   admin-web/tools/test.sh server|client|lint|build|all [--grep шаблон]
# Выход: 1–5 строк вердикта; полный лог — /tmp/mb10-tools/<часть>.log. Код 0 — всё зелёное, 1 — нет.
. "$(dirname "$0")/_lib.sh"
part=${1:-all}; shift || true
grep_pat=""; [ "${1:-}" = "--grep" ] && grep_pat=${2:-}
rc=0

run_part() { # имя  каталог  команда...
  local name=$1 dir=$2; shift 2
  local nd start log="$LOGS/$name.log"
  nd=$(node_dir "$dir"); start=$SECONDS
  (cd "$ADMIN/$dir" && PATH="$nd:$PATH" "$@") >"$log" 2>&1; local code=$?
  echo "$name|$code|$((SECONDS-start))|$log"
}

report() { # имя|код|сек|лог
  IFS='|' read -r name code secs log <<<"$1"
  case $name in
    server)
      local t p f s; t=$(grep -E '^ℹ tests ' "$log" | awk '{print $3}'); p=$(grep -E '^ℹ pass ' "$log" | awk '{print $3}'); f=$(grep -E '^ℹ fail ' "$log" | awk '{print $3}'); s=$(grep -E '^ℹ skipped ' "$log" | awk '{print $3}')
      if [ -z "$t" ]; then echo "server: НЕ ЗАПУСТИЛСЯ ($(dur "$secs")) — хвост лога:"; tail -n 12 "$log"; rc=1; return; fi
      if [ "$code" = 0 ] && [ "${f:-0}" = 0 ]; then echo "server: ок — $p из $t, пропущено ${s:-0}, провалов 0 ($(dur "$secs"))"
      else echo "server: ПРОВАЛ — $f из $t ($(dur "$secs")); упавшие:"; grep -E '^✖' "$log" | sort -u | head -8 | cut -c1-150; rc=1; fi;;
    client)
      local files tests; files=$(grep -E 'Test Files' "$log" | sed 's/^ *//'); tests=$(grep -E '^ *Tests ' "$log" | sed 's/^ *//')
      if [ "$code" = 0 ]; then echo "client: ок — $files; $tests ($(dur "$secs"))"
      else echo "client: ПРОВАЛ ($(dur "$secs")):"; grep -E 'FAIL|×' "$log" | head -8 | cut -c1-160; [ -z "$(grep -E 'FAIL|×' "$log")" ] && tail -n 10 "$log"; rc=1; fi;;
    lint)   if [ "$code" = 0 ]; then echo "lint: ок, предупреждений $(grep -c 'warning' "$log") ($(dur "$secs"))"; else echo "lint: ПРОВАЛ"; tail -n 10 "$log"; rc=1; fi;;
    *)      if [ "$code" = 0 ]; then echo "$name: ок ($(dur "$secs"))"; else echo "$name: ПРОВАЛ ($(dur "$secs")) — хвост:"; tail -n 12 "$log"; rc=1; fi;;
  esac
}

server_cmd=(npm test); [ -n "$grep_pat" ] && server_cmd=(npx tsx --test --test-name-pattern "$grep_pat" 'src/*.test.ts')
client_cmd=(npx vitest run); [ -n "$grep_pat" ] && client_cmd=(npx vitest run -t "$grep_pat")

# Части идут по очереди: на Mac 8 ГБ два тяжёлых Node-процесса одновременно — уже много.
case $part in
  server) report "$(run_part server server "${server_cmd[@]}")";;
  client) report "$(run_part client client bash -c 'npx tsc -b && '"$(printf '%q ' "${client_cmd[@]}")")";;
  lint)   report "$(run_part lint client npm run lint --silent)";;
  build)  report "$(run_part build-server server npm run build --silent)"; report "$(run_part build-client client npm run build --silent)";;
  all)    report "$(run_part server server "${server_cmd[@]}")"
          report "$(run_part client client bash -c 'npx tsc -b && '"$(printf '%q ' "${client_cmd[@]}")")"
          report "$(run_part lint client npm run lint --silent)"
          report "$(run_part build-client client npm run build --silent)";;
  *) echo "использование: test.sh server|client|lint|build|all [--grep шаблон]"; exit 2;;
esac
exit $rc
