#!/usr/bin/env bash
# Живой прогон M5: настоящий Мост (Kotlin) + сервер мира (Godot) + бот; сервер мира убивается посреди забега и поднимается
# снова, бот возвращается в тот же забег и выходит чисто. В конце — проверка документов Моста.
# Запускать на devbox (Linux; Gradle и Godot на Mac не гонять): `timeout 1200 netrun/tools/live_run.sh`.
# Итог — одна строка `LIVE_RUN PASS|FAIL: ...` и код 0|1. Все процессы с жёсткими пределами времени, в конце всё гасится.
# Окружение: BRIDGE_PORT (7410), LINE_PORT (7411), ENET_PORT (7777), GODOT (godot), KEEP_LOGS=1 (не удалять каталог журналов),
# GRAPH=1 (граф узлов W1: сервер мира с --graph, бот graph_run идёт тоннелем node_07 -> node_04, шард берёт в node_04).
set -u
set -m  # у каждого фонового процесса своя группа: kill -- -PID гасит и timeout, и то, что он запустил
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-godot}"
BRIDGE_PORT="${BRIDGE_PORT:-7410}"
LINE_PORT="${LINE_PORT:-7411}"
ENET_PORT="${ENET_PORT:-7777}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/netrun-live.XXXXXX")"
PIDS=()
RESULT=FAIL
REASON="не дошли до конца"

# Без UTF-8 Java пишет в журнал вопросительные знаки.
export LC_ALL=C.UTF-8 LANG=C.UTF-8

# Ключи ролей и данные стенда — тестовые, только для этого прогона.
export NETRUN_KEY_WORLD=kw NETRUN_KEY_MASTER=km NETRUN_KEY_TEST=kt
TOKEN="live-token-t03"
RUNNER="KEY_LIVE_ALICE"
SESSION="s_live000000000001"
SHARD="it_live0000000a001"

sha256() { if command -v sha256sum >/dev/null; then printf %s "$1" | sha256sum | cut -d' ' -f1; else printf %s "$1" | shasum -a 256 | cut -d' ' -f1; fi; }

# Предел времени: timeout (Linux), gtimeout (Mac с coreutils) или perl alarm.
tmo() {
  local secs=$1; shift
  if command -v timeout >/dev/null; then timeout --foreground -k 5 "$secs" "$@"
  elif command -v gtimeout >/dev/null; then gtimeout --foreground -k 5 "$secs" "$@"
  else perl -e 'alarm shift; exec @ARGV' "$secs" "$@"; fi
}

log() { echo "[live_run] $*"; }

cleanup() {
  local p
  for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill -KILL -- "-$p" 2>/dev/null; done
  wait 2>/dev/null
  if [ "$RESULT" != PASS ]; then
    for f in "$WORK"/*.log; do [ -f "$f" ] && { echo "---- $(basename "$f") (хвост) ----"; tail -n 25 "$f"; }; done
  fi
  [ "${KEEP_LOGS:-0}" = 1 ] && echo "журналы: $WORK" || rm -rf "$WORK"
  echo "LIVE_RUN $RESULT: $REASON"
  [ "$RESULT" = PASS ]
}
trap 'cleanup; exit $?' EXIT
trap 'REASON="прервано сигналом"; exit 1' INT TERM

fail() { REASON="$*"; log "ПРОВАЛ: $*"; exit 1; }

# wait_for <секунд> <описание> <команда...> — опрос каждые 0,5 с, без «поспали и посмотрели один раз».
wait_for() {
  local secs=$1 what=$2; shift 2
  local end=$((SECONDS + secs))
  while [ $SECONDS -lt $end ]; do "$@" && return 0; sleep 0.5; done
  fail "не дождались: $what (${secs} с)"
}
has() { grep -q -- "$2" "$1" 2>/dev/null; }
alive() { kill -0 "$1" 2>/dev/null; }

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
for p in "$BRIDGE_PORT" "$ENET_PORT"; do port_open "$p" && fail "порт $p уже занят (остался процесс прошлого прогона?)"; done
command -v "$GODOT" >/dev/null || fail "нет $GODOT в PATH (на devbox: . ~/netrun-env.sh)"
cd "$ROOT" || fail "нет каталога $ROOT"

log "сборка Моста"
tmo 600 ./gradlew -q :netrun-bridge:installDist >"$WORK/gradle.log" 2>&1 || { tail -n 30 "$WORK/gradle.log"; fail "не собрался Мост"; }
[ -d netrun/.godot ] || { log "импорт проекта Godot"; tmo 180 "$GODOT" --headless --path netrun --import >"$WORK/import.log" 2>&1; }

# --- Данные стенда: узел, терминал с токеном, игрок (обучение пройдено), активная сессия, дека, шард в узле ---
SHARD_NODE=node_07
SERVER_GRAPH=""
BOT_ARGS="--bot=ghost_run"
EXTRA_NODE=""
if [ "${GRAPH:-0}" = 1 ]; then
  SHARD_NODE=node_04
  SERVER_GRAPH="--graph"
  BOT_ARGS="--bot=graph_run --bot-route=node_04"
  EXTRA_NODE=', "node_04": {"title": "Склад запчастей", "tier": "BASE", "tutorial": false, "lockdown_until": 0, "eddies": 0}'
fi
RKEY_DOC="r_$(sha256 "$RUNNER" | cut -c1-32)"
cat >"$WORK/seed.json" <<JSON
{
  "settings": {"global": {"auditor_period_s": 2}},
  "node": {"node_07": {"title": "Серый узел", "tier": "STANDARD", "tutorial": false, "lockdown_until": 0, "eddies": 0}$EXTRA_NODE},
  "terminal": {"t03": {"node": "node_07", "label": "стенд", "token_sha256": "$(sha256 "$TOKEN")", "silent": false}},
  "runner": {"$RKEY_DOC": {"key": "$RUNNER", "callsign": "Призрак", "blocked": false, "runs": 1, "tutorial_done": true}},
  "session": {"$SESSION": {"state": "active", "terminal": "t03", "node": "node_07", "runner": "$RUNNER", "callsign": "Призрак",
    "enter_rid": "e-live", "confirmed_at": 1, "loot_eddies": 0, "outcome": null, "finished_at": 0, "world": {}}},
  "deck": {"$SESSION": {"items": ["it_live0000000d001", "it_live0000000d002"], "protected": "it_live0000000d001"}},
  "item": {
    "it_live0000000d001": {"owner": "deck:$SESSION", "kind": "DAEMON", "payload": "daemon:ghost_1", "protected": true, "origin": "phone:$RUNNER", "in_transfer": null, "out_transfer": null, "handover": null},
    "it_live0000000d002": {"owner": "deck:$SESSION", "kind": "DAEMON", "payload": "daemon:jitter_1", "protected": false, "origin": "phone:$RUNNER", "in_transfer": null, "out_transfer": null, "handover": null},
    "$SHARD": {"owner": "node:$SHARD_NODE", "kind": "SHARD", "payload": "shard-live", "protected": false, "origin": "node:$SHARD_NODE", "in_transfer": null, "out_transfer": null, "handover": null}
  }
}
JSON

# --- 1. Мост ---
log "Мост на порту $BRIDGE_PORT"
tmo 900 netrun-bridge/build/install/netrun-bridge/bin/netrun-bridge --port "$BRIDGE_PORT" --line-port "$LINE_PORT" \
  --db "$WORK/bridge.db" --test --seed "$WORK/seed.json" >"$WORK/bridge.log" 2>&1 &
BRIDGE_PID=$!; PIDS+=("$BRIDGE_PID")
wait_for 60 "порт Моста $BRIDGE_PORT" port_open "$BRIDGE_PORT"
alive "$BRIDGE_PID" || fail "Мост завершился при запуске"

start_world() { # $1 — имя журнала
  tmo 600 "$GODOT" --headless --path netrun -- --bridge="ws://127.0.0.1:$BRIDGE_PORT" --bridge-key=kw --port="$ENET_PORT" --grace=20 $SERVER_GRAPH >"$WORK/$1.log" 2>&1 &
  WORLD_PID=$!; PIDS+=("$WORLD_PID")
}

# --- 2. Сервер мира №1, бот ---
log "сервер мира №1"
start_world world1
W1=$WORLD_PID
wait_for 90 "снимок Моста у сервера мира №1" has "$WORK/world1.log" "снимок Моста"
has "$WORK/world1.log" "активных сессий 1" || fail "сервер мира №1 не увидел активную сессию"

log "бот"
tmo 240 "$GODOT" --headless --path netrun -- $BOT_ARGS --bot-reconnect --host=127.0.0.1 --port="$ENET_PORT" \
  --token="t03:$TOKEN" --bot-hold=10 --exit-after=200 >"$WORK/bot.log" 2>&1 &
BOT_PID=$!; PIDS+=("$BOT_PID")
wait_for 90 "шард взят и записан в Мосте" has "$WORK/world1.log" "take $SHARD ok"
has "$WORK/bot.log" "итог" && fail "бот закончил до убийства сервера"

# --- 3. Убиваем сервер мира посреди забега и поднимаем заново ---
log "kill -9 сервера мира №1 (бот несёт шард)"
kill -KILL -- "-$W1" 2>/dev/null
wait "$W1" 2>/dev/null
alive "$BOT_PID" || fail "бот завершился вместе с сервером: $(tail -n 3 "$WORK/bot.log" | tr '\n' ' ')"
log "сервер мира №2"
start_world world2
wait_for 90 "снимок Моста у сервера мира №2" has "$WORK/world2.log" "снимок Моста"
has "$WORK/world2.log" "активных сессий 1" || fail "после рестарта сервер мира не нашёл активную сессию"
has "$WORK/world2.log" "шард $SHARD" || fail "после рестарта сервер мира не нашёл шард $SHARD"

# --- 4. Бот возвращается и выходит чисто ---
wait_for 120 "завершение бота" bash -c "! kill -0 $BOT_PID 2>/dev/null"
wait "$BOT_PID"; BOT_RC=$?
has "$WORK/bot.log" "итог: clean" || fail "бот не вышел чисто (код $BOT_RC): $(grep 'итог' "$WORK/bot.log" | tail -n 1)"
has "$WORK/bot.log" "переподключений: [1-9]" || fail "бот не переподключался — сервер, видимо, не убивался посреди забега"
wait_for 30 "run.finish сервера мира №2" has "$WORK/world2.log" "run.finish $SESSION clean: ok"

# --- 5. Документы Моста ---
log "проверка документов Моста"
tmo 120 "$GODOT" --headless --path netrun -s res://tools/check_bridge.gd -- --bridge="ws://127.0.0.1:$BRIDGE_PORT/netrun/v1" --key=kw \
  --session="$SESSION" --runner="$RUNNER" --shard="$SHARD" --wait=60 >"$WORK/check.log" 2>&1
CHECK_RC=$?
grep '^\[check\]' "$WORK/check.log"
[ "$CHECK_RC" = 0 ] || fail "документы Моста не сошлись (см. check.log)"

RESULT=PASS
REASON="сервер убит посреди забега, бот вернулся ($(grep -o 'переподключений: [0-9]*' "$WORK/bot.log")), шард у игрока в outbox, аудитор чист"
