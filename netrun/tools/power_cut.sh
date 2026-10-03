#!/usr/bin/env bash
# Учения «выдернули питание» (L4): Мост (SQLite в WAL) + сервер мира + боты посреди забегов, затем ВСЁ разом `kill -9`,
# подъём заново и проверка: ни один предмет не пропал и не раздвоился (число и набор id те же, аудитор чист), сессии
# закрыты или продолжены (открытых не остаётся), документы узлов и цель мастера на месте (версии не откатились).
# Запускать на devbox (Linux; Gradle и Godot на Mac не гонять):  timeout 900 netrun/tools/power_cut.sh
# Итог — одна строка `POWER_CUT PASS|FAIL: ...` и код 0|1. Все процессы гасятся в конце и по Ctrl-C/SIGTERM.
# Параметры: --bots=4, --seed=<число>, --dir=<каталог журналов>. Окружение: BRIDGE_PORT (7410), LINE_PORT (7411), ENET_PORT (7777), GODOT (godot).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-godot}"
BRIDGE_PORT="${BRIDGE_PORT:-7410}"
LINE_PORT="${LINE_PORT:-7411}"
ENET_PORT="${ENET_PORT:-7777}"
BOTS=4; SEED=$$; DIR=""
for a in "$@"; do
  case "$a" in
    --bots=*) BOTS="${a#*=}" ;;
    --seed=*) SEED="${a#*=}" ;;
    --dir=*) DIR="${a#*=}" ;;
    *) echo "неизвестный параметр: $a" >&2; exit 2 ;;
  esac
done
export LC_ALL=C.UTF-8 LANG=C.UTF-8
export NETRUN_KEY_WORLD=kw NETRUN_KEY_MASTER=km NETRUN_KEY_TEST=kt
RANDOM=$SEED
POOL=40
FAR=4102444800000  # 2100 год, мс Unix: локдаун и цель, которые не должны сработать за время учений

WORK="${DIR:-${TMPDIR:-/tmp}/netrun-powercut.$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$WORK" || exit 2
WORK="$(cd "$WORK" && pwd)"
RESULT=FAIL; REASON="не дошли до конца"; SUMMARY_LINE=""
BRIDGE_PID=""; WORLD_PID=""; LOOP_PIDS=()
START=$SECONDS

tmo() { local secs=$1; shift; timeout --foreground -k 5 "$secs" "$@"; }
ev() { echo "[$((SECONDS - START))с] $*" | tee -a "$WORK/events.log"; }
sha256() { printf %s "$1" | sha256sum | cut -d' ' -f1; }
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
has() { grep -q -- "$2" "$1" 2>/dev/null; }
# «Выдернуть питание»: все процессы прогона (Мост — по пути базы, остальные — по каталогу) гасятся SIGKILL одним махом.
power_cut() { pkill -KILL -f -- "soak-dir=$WORK" 2>/dev/null; pkill -KILL -f -- "$WORK/bridge.db" 2>/dev/null; return 0; }

cleanup() {
  trap '' INT TERM
  touch "$WORK/stop"
  local p
  for p in "${LOOP_PIDS[@]:-}"; do [ -n "$p" ] && kill -KILL "$p" 2>/dev/null; done
  power_cut; wait 2>/dev/null; sleep 0.5; power_cut
  if [ "$RESULT" != PASS ]; then
    for f in "$WORK"/bridge*.log "$WORK"/world*.log; do [ -f "$f" ] && { echo "---- $(basename "$f") (хвост) ----"; tail -n 15 "$f"; }; done
  fi
  [ -n "$SUMMARY_LINE" ] && echo "$SUMMARY_LINE" || echo "POWER_CUT $RESULT: $REASON"
  echo "журналы: $WORK"
  [ "$RESULT" = PASS ]
}
trap 'cleanup; exit $?' EXIT
trap 'REASON="прервано сигналом"; exit 1' INT TERM
fail() { REASON="$*"; ev "ПРОВАЛ: $*"; exit 1; }

for p in "$BRIDGE_PORT" "$ENET_PORT"; do port_open "$p" && fail "порт $p уже занят (остался процесс прошлого прогона?)"; done
command -v "$GODOT" >/dev/null || fail "нет $GODOT в PATH (на devbox: . ~/netrun-env.sh)"
command -v python3 >/dev/null || fail "нужен python3"
cd "$ROOT" || fail "нет каталога $ROOT"

ev "каталог журналов $WORK, ботов $BOTS, seed $SEED"
ev "сборка Моста"
tmo 900 ./gradlew -q :netrun-bridge:installDist >"$WORK/gradle.log" 2>&1 || { tail -n 30 "$WORK/gradle.log"; fail "не собрался Мост"; }
[ -d netrun/.godot ] || { ev "импорт проекта Godot"; tmo 180 "$GODOT" --headless --path netrun --import >"$WORK/import.log" 2>&1; }

# --- Данные: как в soak.sh + холодный узел с локдауном и цель мастера на рабочем узле (проверяем, что они переживут обрыв) ---
python3 - "$WORK/seed.json" "$BOTS" "$POOL" "$FAR" <<'PY'
import hashlib, json, sys
out, bots, pool, far = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
sha = lambda s: hashlib.sha256(s.encode()).hexdigest()
d = {"settings": {"global": {"auditor_period_s": 5, "soft_ice_reentry_pause_s": 2}},
     "node": {"node_07": {"title": "Серый узел", "tier": "STANDARD", "tutorial": False, "lockdown_until": 0, "eddies": 0},
              "node_cold": {"title": "Холодный узел", "tier": "STANDARD", "tutorial": False, "lockdown_until": far, "eddies": 0}},
     "node_cfg": {"node_07": {"goal": {"kind": "open", "value": 0, "deadline": far, "set_at": 1, "done": False, "result": None}}},
     "terminal": {}, "runner": {}, "session": {}, "deck": {}, "item": {}}
for n in range(1, 13):  # граф data/graph.json — 12 узлов; run.finish в узле без документа Моста даёт not_found
    nid = "node_%02d" % n
    if nid not in d["node"]:
        d["node"][nid] = {"title": nid, "tier": "STANDARD", "tutorial": False, "lockdown_until": 0, "eddies": 0}
d["item"]["it_soak_shard00000"] = {"owner": "node:node_07", "kind": "SHARD", "payload": "shard-soak", "protected": False,
    "origin": "node:node_07", "in_transfer": None, "out_transfer": None, "handover": None}
for b in range(1, bots + 1):
    key = "KEY_SOAK_B%d" % b
    d["terminal"]["t%02d" % b] = {"node": "node_07", "label": "cut %d" % b, "token_sha256": sha("soak-token-%d" % b), "silent": False}
    d["runner"]["r_" + sha(key)[:32]] = {"key": key, "callsign": "Cut%d" % b, "blocked": False, "runs": 1, "tutorial_done": True}
    for k in range(1, pool + 1):
        for j in "ab":
            d["item"]["it_soak_b%d_%d%s" % (b, k, j)] = {"owner": "inbox:" + key, "kind": "DAEMON", "payload": "daemon:ghost_1",
                "protected": j == "a", "origin": "phone:" + key, "in_transfer": None, "out_transfer": None, "handover": None}
json.dump(d, open(out, "w"), ensure_ascii=False)
PY
ITEMS_EXPECTED=$(python3 -c "import json; print(len(json.load(open('$WORK/seed.json'))['item']))")
ev "в seed $ITEMS_EXPECTED предметов"

start_bridge() { # $1 — суффикс журнала
  tmo 1200 netrun-bridge/build/install/netrun-bridge/bin/netrun-bridge --port "$BRIDGE_PORT" --line-port "$LINE_PORT" \
    --db "$WORK/bridge.db" --test --seed "$WORK/seed.json" >"$WORK/bridge$1.log" 2>&1 &
  BRIDGE_PID=$!
  local end=$((SECONDS + 90)); until port_open "$BRIDGE_PORT"; do
    [ $SECONDS -ge $end ] && fail "Мост не открыл порт"
    kill -0 "$BRIDGE_PID" 2>/dev/null || fail "Мост завершился при запуске: $(tail -n 3 "$WORK/bridge$1.log")"
    sleep 0.5
  done
}
start_world() { # $1 — суффикс журнала
  tmo 1200 "$GODOT" --headless --path netrun -- --bridge="ws://127.0.0.1:$BRIDGE_PORT" --bridge-key=kw --port="$ENET_PORT" --grace=20 \
    --soak-dir="$WORK" --soak-role=world >"$WORK/world$1.log" 2>&1 &
  WORLD_PID=$!
  local end=$((SECONDS + 90))
  until has "$WORK/world$1.log" "снимок Моста"; do
    [ $SECONDS -ge $end ] && fail "сервер мира не взял снимок Моста"
    kill -0 "$WORLD_PID" 2>/dev/null || fail "сервер мира завершился при запуске"
    sleep 0.5
  done
}
bot_loop() { # $1 — бот, $2 — с какого набора предметов начинать (вторая волна берёт непочатые)
  local b=$1 k=$(($2 - 1)) scen flags
  while [ ! -f "$WORK/stop" ]; do
    k=$((k + 1))
    scen=ghost_run; [ $((RANDOM % 3)) -eq 0 ] && scen=exposed_run
    flags=""; [ "$b" -ne 1 ] && flags="--no-shard"
    # shellcheck disable=SC2086
    tmo 200 "$GODOT" --headless --path netrun -s res://tools/soak_run.gd -- --bridge="ws://127.0.0.1:$BRIDGE_PORT/netrun/v1" --key=kt \
      --runner="KEY_SOAK_B$b" --terminal="$(printf 't%02d' "$b")" --token="soak-token-$b" --items="it_soak_b${b}_${k}a,it_soak_b${b}_${k}b" \
      --host=127.0.0.1 --port="$ENET_PORT" --scenario="$scen" --tag="b$b-r$k" $flags --soak-dir="$WORK" >>"$WORK/bot_$b.log" 2>&1
    echo "[power-cut] bot=$b run=$k rc=$?" >>"$WORK/bot_$b.log"
    sleep $((1 + RANDOM % 3))
  done
}
start_bots() { for b in $(seq 1 "$BOTS"); do bot_loop "$b" "$1" & LOOP_PIDS+=("$!"); sleep 0.3; done; }
audit() { # $1... — аргументы soak_audit.gd; вывод в audit.last
  tmo 60 "$GODOT" --headless --path netrun -s res://tools/soak_audit.gd -- --bridge="ws://127.0.0.1:$BRIDGE_PORT/netrun/v1" --key=kw "$@" --soak-dir="$WORK" >"$WORK/audit.last" 2>&1
}
field() { grep -o "$1=[0-9]*" "$WORK/audit.last" | head -1 | cut -d= -f2; }

# --- Волна 1: боты идут, ждём, пока хотя бы две сессии откроются посреди забега, и «выдёргиваем питание» ---
ev "Мост, сервер мира, боты (волна 1)"
start_bridge ""; start_world ""; start_bots 1
end=$((SECONDS + 120)); open=0
while [ $SECONDS -lt $end ]; do
  sleep 4
  audit --dump="$WORK/before.json" || continue
  open=$(field sessions_open); [ "${open:-0}" -ge 2 ] && break
done
[ "${open:-0}" -ge 2 ] || fail "за 120 с ни у кого не открылись забеги (сессий открыто: ${open:-?})"
sleep 1
WAL=$(stat -c %s "$WORK/bridge.db-wal" 2>/dev/null || echo 0)
ev "ПИТАНИЕ ВЫДЕРНУТО: kill -9 Мосту, серверу мира и ботам, сессий открыто на момент слепка: $open, WAL ${WAL} байт"
touch "$WORK/stop"; power_cut
for p in "${LOOP_PIDS[@]}"; do kill -KILL "$p" 2>/dev/null; done; wait 2>/dev/null; LOOP_PIDS=(); power_cut; rm -f "$WORK/stop"
sleep 2
pgrep -f -- "soak-dir=$WORK" >/dev/null && fail "после kill -9 остались процессы прогона"

# --- Включили питание: тот же файл базы, тот же seed (дописывает только недостающее) ---
ev "питание вернулось: Мост и сервер мира заново"
start_bridge "_2"; start_world "_2"
ev "боты (волна 2): продолжают на непочатых предметах"
start_bots 21
sleep 30
touch "$WORK/stop"
end=$((SECONDS + 100))
while [ $SECONDS -lt $end ] && pgrep -f -- "--tag=b.*soak-dir=$WORK" >/dev/null; do sleep 2; done
pkill -KILL -f -- "--tag=b.*soak-dir=$WORK" 2>/dev/null
end=$((SECONDS + 90)); open=1
while [ $SECONDS -lt $end ]; do  # недоигранные сессии прошлой жизни закрывает сервер мира по окну возврата (20 с)
  audit --items="$ITEMS_EXPECTED" --dump="$WORK/after.json"
  open=$(field sessions_open); [ "${open:-1}" = 0 ] && break
  sleep 5
done
sleep 7  # аудитор Моста (период 5 с) проходит по итоговому состоянию
audit --items="$ITEMS_EXPECTED" --dump="$WORK/after.json"; arc=$?
cp "$WORK/audit.last" "$WORK/summary.txt"
ALERTS_AUD=$(field alerts_auditor); ALERTS_AUD=${ALERTS_AUD:-?}
OPEN_END=$(field sessions_open); OPEN_END=${OPEN_END:-?}
ITEMS_END=$(field items); ITEMS_END=${ITEMS_END:-?}

# --- Сверка слепков до и после ---
COMPARE=$(python3 - "$WORK/seed.json" "$WORK/before.json" "$WORK/after.json" <<'PY'
import json, sys
seed, a, b = (json.load(open(p)) for p in sys.argv[1:4])
why = []
want = set(seed["item"])
for name, d in (("до", a), ("после", b)):
    got = set(d["items"])
    if got != want:
        why.append("предметы %s: нет %d, лишних %d" % (name, len(want - got), len(got - want)))
for nid, n in a["node"].items():
    m = b["node"].get(nid)
    if m is None: why.append("документ узла %s пропал" % nid); continue
    if m["ver"] < n["ver"]: why.append("версия узла %s откатилась %s→%s" % (nid, n["ver"], m["ver"]))
    for k in ("tier", "lockdown_until"):
        if m["data"].get(k) != n["data"].get(k): why.append("узел %s поле %s изменилось" % (nid, k))
for nid, n in a["node_cfg"].items():
    m = b["node_cfg"].get(nid)
    if m is None or m["data"].get("goal") != n["data"].get("goal"): why.append("цель мастера узла %s не сохранилась" % nid)
for sid in a["sessions"]:
    if sid not in b["sessions"]: why.append("сессия %s пропала" % sid)
print("; ".join(why))
PY
)
VERDICT=PASS; WHY=""
[ -n "$COMPARE" ] && { VERDICT=FAIL; WHY="$WHY $COMPARE;"; }
[ "$arc" != 0 ] && { VERDICT=FAIL; WHY="$WHY итоговый аудит rc=$arc (число предметов $ITEMS_END, ждали $ITEMS_EXPECTED);"; }
[ "$ALERTS_AUD" != 0 ] && { VERDICT=FAIL; WHY="$WHY тревоги аудитора $ALERTS_AUD;"; }
[ "$OPEN_END" != 0 ] && { VERDICT=FAIL; WHY="$WHY открытых сессий в конце: $OPEN_END;"; }
SUMMARY_LINE="POWER_CUT $VERDICT: предметов $ITEMS_END из $ITEMS_EXPECTED, тревог аудитора $ALERTS_AUD, открытых сессий $OPEN_END, сессий на момент обрыва ≥2, WAL ${WAL} байт,${WHY:+ причины:$WHY}"
RESULT=$VERDICT; REASON="$SUMMARY_LINE"
[ "$VERDICT" = PASS ]
