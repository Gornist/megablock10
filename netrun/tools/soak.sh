#!/usr/bin/env bash
# Долгий прогон (P7): настоящий Мост (--test --seed) + сервер мира (--bridge) + N ботов отдельными процессами, которые бесконечно
# (до конца срока) повторяют случайные забеги: чистый, под ICE, экстренный выход, обрыв с возвратом и без. Раз в ~20 минут сервер мира
# убивается и поднимается (плановое убийство), время от времени убивается бот посреди забега. Потери и задержка сети — на стороне
# бота (NetClient.impair_*): tc netem требует root, на devbox его нет; эмуляция честна для клиента (потеря позиций и снимков,
# повтор надёжных пакетов как лишние 200 мс, задержка в обе стороны), но не трогает UDP на проводе.
# Запускать на devbox (Linux; Gradle и Godot на Mac не гонять):
#   timeout 4500 netrun/tools/soak.sh --hours=1
# Итог — одна строка `SOAK PASS|FAIL: ...` и код 0|1. Все процессы гасятся в конце и по Ctrl-C/SIGTERM.
# Параметры: --hours=1 (дробное можно: 0.1), --bots=8, --world-kill-min=20, --bot-kill-min=7, --seed=<число>, --dir=<каталог журналов>,
# --netem=mix|none (mix: у ботов 3 и 4 из каждых четырёх — потеря 5%/задержка 60±30 мс и потеря 15%/150±80 мс).
# Окружение: BRIDGE_PORT (7410), LINE_PORT (7411), ENET_PORT (7777), GODOT (godot).
# Журналы в каталоге: summary.txt, bridge.log, world_N.log (по экземпляру), bot_B.log (строки `[soak-run]` и `[soak-loop]`),
# audit.log (проходы soak_audit.gd), rss.csv (экземпляр,секунды жизни,КБ), events.log (что делал оркестратор).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-godot}"
BRIDGE_PORT="${BRIDGE_PORT:-7410}"
LINE_PORT="${LINE_PORT:-7411}"
ENET_PORT="${ENET_PORT:-7777}"
HOURS=1; BOTS=8; WORLD_KILL_MIN=20; BOT_KILL_MIN=7; SEED=$$; DIR=""; NETEM=mix
for a in "$@"; do
  case "$a" in
    --hours=*) HOURS="${a#*=}" ;;
    --bots=*) BOTS="${a#*=}" ;;
    --world-kill-min=*) WORLD_KILL_MIN="${a#*=}" ;;
    --bot-kill-min=*) BOT_KILL_MIN="${a#*=}" ;;
    --seed=*) SEED="${a#*=}" ;;
    --dir=*) DIR="${a#*=}" ;;
    --netem=*) NETEM="${a#*=}" ;;
    *) echo "неизвестный параметр: $a" >&2; exit 2 ;;
  esac
done
export LC_ALL=C.UTF-8 LANG=C.UTF-8
export NETRUN_KEY_WORLD=kw NETRUN_KEY_MASTER=km NETRUN_KEY_TEST=kt
RANDOM=$SEED

# Сроки в секундах. Для коротких проб интервалы сжимаются, чтобы успеть и убить мир, и убить бота.
DUR=$(awk -v h="$HOURS" 'BEGIN{printf "%d", h*3600}')
WORLD_KILL_S=$(awk -v m="$WORLD_KILL_MIN" -v d="$DUR" 'BEGIN{w=m*60; if (d/3 < w) w=d/3; printf "%d", w}')
BOT_KILL_S=$(awk -v m="$BOT_KILL_MIN" -v d="$DUR" 'BEGIN{w=m*60; if (d/4 < w) w=d/4; printf "%d", w}')
AUDIT_S=300
[ "$DUR" -lt 900 ] && AUDIT_S=$((DUR / 3 > 60 ? DUR / 3 : 60))
POOL=$((DUR / 12 + 20))  # забегов на бота в запасе (2 предмета на забег; бот делает забег раз в 15–25 с — пауза 5–20 с между забегами)

WORK="${DIR:-${TMPDIR:-/tmp}/netrun-soak.$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$WORK" || exit 2
WORK="$(cd "$WORK" && pwd)"
RESULT=FAIL
REASON="не дошли до конца"
LOOP_PIDS=()
BRIDGE_PID=""
WORLD_PID=""
WORLD_N=0
WORLD_T0=0
WORLD_UNEXPECTED=0
WORLD_PLANNED=0
BOT_KILLS=0
START=$SECONDS
SUMMARY_LINE=""

tmo() { local secs=$1; shift; timeout --foreground -k 5 "$secs" "$@"; }
ev() { echo "[$((SECONDS - START))с] $*" | tee -a "$WORK/events.log"; }
sha256() { printf %s "$1" | sha256sum | cut -d' ' -f1; }
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
has() { grep -q -- "$2" "$1" 2>/dev/null; }

killall_mine() { pkill -KILL -f -- "soak-dir=$WORK" 2>/dev/null; pkill -KILL -f -- "$WORK/bridge.db" 2>/dev/null; return 0; }

cleanup() {
  trap '' INT TERM
  touch "$WORK/stop"
  local p
  for p in "${LOOP_PIDS[@]:-}"; do [ -n "$p" ] && kill -KILL "$p" 2>/dev/null; done
  killall_mine
  [ -n "$BRIDGE_PID" ] && kill -KILL "$BRIDGE_PID" 2>/dev/null
  wait 2>/dev/null
  sleep 0.5; killall_mine
  if [ "$RESULT" != PASS ]; then
    for f in "$WORK"/bridge.log "$WORK"/world_*.log; do [ -f "$f" ] && { echo "---- $(basename "$f") (хвост) ----"; tail -n 15 "$f"; }; done
  fi
  [ -n "$SUMMARY_LINE" ] && echo "$SUMMARY_LINE" || echo "SOAK $RESULT: $REASON"
  echo "журналы: $WORK"
  [ "$RESULT" = PASS ]
}
trap 'cleanup; exit $?' EXIT
trap 'REASON="прервано сигналом"; exit 1' INT TERM

fail() { REASON="$*"; ev "ПРОВАЛ: $*"; exit 1; }

for p in "$BRIDGE_PORT" "$ENET_PORT"; do port_open "$p" && fail "порт $p уже занят (остался процесс прошлого прогона?)"; done
command -v "$GODOT" >/dev/null || fail "нет $GODOT в PATH (на devbox: . ~/netrun-env.sh)"
command -v python3 >/dev/null || fail "нужен python3 (генерация данных Моста)"
cd "$ROOT" || fail "нет каталога $ROOT"

ev "каталог журналов $WORK; срок ${DUR} с, ботов $BOTS, убийство мира раз в ${WORLD_KILL_S} с, бота — раз в ${BOT_KILL_S} с, seed $SEED"
ev "сборка Моста"
tmo 900 ./gradlew -q :netrun-bridge:installDist >"$WORK/gradle.log" 2>&1 || { tail -n 30 "$WORK/gradle.log"; fail "не собрался Мост"; }
[ -d netrun/.godot ] || { ev "импорт проекта Godot"; tmo 180 "$GODOT" --headless --path netrun --import >"$WORK/import.log" 2>&1; }

# Пауза после выброса ICE (локдаун узла) сжата с 10 минут до 2 с: иначе после первого выброса весь узел закрыт для входа.
# --- Данные: узел, шард, по терминалу и игроку на бота, запас предметов в inbox каждого игрока (забег сдаёт 2) ---
python3 - "$WORK/seed.json" "$BOTS" "$POOL" <<'PY'
import base64, hashlib, json, sys
out, bots, pool = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
sha = lambda s: hashlib.sha256(s.encode()).hexdigest()
# node_lockdown_s = 2: после выброса ICE узел закрыт для входа не 10 минут, а 2 с (иначе первый выброс запирает узел — и забеги отказывают).
# Узлы стенда — те, куда сервер мира ведёт терминалы по graph.json (entries / default_entry): терминал бота и узел сессии в Мосте совпадают.
g = json.load(open("netrun/data/graph.json"))
node_of = lambda t: g["entries"].get(t, g["default_entry"])
d = {"settings": {"global": {"auditor_period_s": 5, "soft_ice_reentry_pause_s": 2, "node_lockdown_s": 2}},
     "node": {}, "terminal": {}, "runner": {}, "session": {}, "deck": {}, "item": {}}
for b in range(1, bots + 1):
    nid = node_of("t%02d" % b)
    if nid not in d["node"]:
        d["node"][nid] = {"title": g["nodes"][nid]["title"], "tier": "STANDARD", "tutorial": False, "lockdown_until": 0, "eddies": 0}
        for s in range(2):   # шарды узла: слот опустеет после выноса и пополнится из них
            d["item"]["it_soak_shard_%s_%d" % (nid, s)] = {"owner": "node:" + nid, "kind": "SHARD", "payload": "shard-soak", "protected": False,
                "origin": "node:" + nid, "in_transfer": None, "out_transfer": None, "handover": None,
                # shard.tier нужен Мосту, чтобы run.breach выбрал это хранилище (без него хранилище «не лежит в узле» и взлом ничего не открывает)
                "shard": {"tier": 1, "title": "Шард стенда", "decrypted": True, "encrypted": False}}
for b in range(1, bots + 1):
    key = "KEY_SOAK_B%d" % b
    t = "t%02d" % b
    d["terminal"][t] = {"node": node_of(t), "label": "soak %d" % b, "token_sha256": sha("soak-token-%d" % b), "silent": False}
    d["runner"]["r_" + sha(key)[:32]] = {"key": key, "callsign": "Soak%d" % b, "blocked": False, "runs": 1, "tutorial_done": True}
    for k in range(1, pool + 1):
        for j in "ab":
            item = {"owner": "inbox:" + key, "kind": "DAEMON", "payload": "daemon:ghost_1",
                "protected": j == "a", "origin": "phone:" + key, "in_transfer": None, "out_transfer": None, "handover": None}
            if b == 1:
                # Бот-вор: Призрак (защищённый, id предмета — ghost-демон бота) и Извлечение — открывает хранилище взломом (vault_requires_open).
                # Payload — настоящая карточка демона (ItemPayloadCodec: DAEMON|id|имя base64|цепочка|уровень|эффект): по ней Мост проверяет run.breach
                # (с payload «daemon:ghost_1» он отвечает bad_request). Разобранное поле daemon, которое сервер мира читает для деки, в seed
                # Мост сам не дописывает (только при приёме настоящей карточки) — пишем то же самое сами.
                name, cells, effect = ("Призрак", "1C,BD", "GHOST") if j == "a" else ("Извлечение", "E9,1C", "EXTRACT_SHARD")
                item["payload"] = "DAEMON|it_soak_b1_%d%s|%s|%s|1|%s" % (k, j, base64.b64encode(name.encode()).decode(), cells, effect)
                item["daemon"] = {"effect": effect, "tier": 1, "name": name, "cells": cells.split(",")}
            d["item"]["it_soak_b%d_%d%s" % (b, k, j)] = item
json.dump(d, open(out, "w"), ensure_ascii=False)
print(len(d["item"]))
PY
ITEMS_EXPECTED=$(python3 -c "import json,sys; print(len(json.load(open('$WORK/seed.json'))['item']))")
ev "в seed $ITEMS_EXPECTED предметов"

# --- Мост ---
ev "Мост на порту $BRIDGE_PORT"
tmo $((DUR + 900)) netrun-bridge/build/install/netrun-bridge/bin/netrun-bridge --port "$BRIDGE_PORT" --line-port "$LINE_PORT" \
  --db "$WORK/bridge.db" --test --seed "$WORK/seed.json" >"$WORK/bridge.log" 2>&1 &
BRIDGE_PID=$!
end=$((SECONDS + 90)); until port_open "$BRIDGE_PORT"; do [ $SECONDS -ge $end ] && fail "Мост не открыл порт"; kill -0 "$BRIDGE_PID" 2>/dev/null || fail "Мост завершился при запуске"; sleep 0.5; done

# --- Сервер мира ---
start_world() {
  WORLD_N=$((WORLD_N + 1))
  tmo $((DUR + 900)) "$GODOT" --headless --path netrun -- --bridge="ws://127.0.0.1:$BRIDGE_PORT" --bridge-key=kw --port="$ENET_PORT" --grace=20 \
    --soak-dir="$WORK" --soak-role=world >"$WORK/world_$WORLD_N.log" 2>&1 &
  WORLD_PID=$!
  WORLD_T0=$SECONDS
  local end=$((SECONDS + 90))
  until has "$WORK/world_$WORLD_N.log" "снимок Моста"; do
    [ $SECONDS -ge $end ] && fail "сервер мира №$WORLD_N не взял снимок Моста"
    kill -0 "$WORLD_PID" 2>/dev/null || fail "сервер мира №$WORLD_N завершился при запуске"
    sleep 0.5
  done
}
world_rss_kb() { local p m=0 r; for p in $(pgrep -f -- "soak-dir=$WORK --soak-role=world"); do r=$(ps -o rss= -p "$p" 2>/dev/null | tr -d ' '); [ -n "$r" ] && [ "$r" -gt "$m" ] && m=$r; done; echo "$m"; }
sample_rss() { echo "$WORLD_N,$((SECONDS - WORLD_T0)),$(world_rss_kb)" >>"$WORK/rss.csv"; }
kill_world() { pkill -KILL -f -- "soak-dir=$WORK --soak-role=world" 2>/dev/null; wait "$WORLD_PID" 2>/dev/null; }

ev "сервер мира №1"
start_world

# --- Боты ---
pick_run() { # печатает «сценарий|сбой» по весам: чистый 40, под ICE 22, экстренный 15, обрыв с возвратом 12, без возврата 11
  local r=$((RANDOM % 100))
  if [ $r -lt 40 ]; then echo "ghost_run|"
  elif [ $r -lt 62 ]; then echo "exposed_run|"
  elif [ $r -lt 77 ]; then echo "ghost_run|emergency"
  elif [ $r -lt 89 ]; then echo "ghost_run|drop_return"
  else echo "ghost_run|drop_gone"; fi
}
netem_flags() { # $1 — номер бота
  [ "$NETEM" = none ] && return
  case $((($1 - 1) % 4)) in
    2) echo "--net-loss=0.05 --net-delay-ms=60 --net-jitter-ms=30" ;;
    3) echo "--net-loss=0.15 --net-delay-ms=150 --net-jitter-ms=80" ;;
  esac
}
bot_loop() { # $1 — номер бота; бот 1 единственный берёт шард (он один на узел)
  local b=$1 k=0 pick scen chaos flags rc
  RANDOM=$((SEED + b))
  while [ ! -f "$WORK/stop" ]; do
    while [ -f "$WORK/world.down" ] && [ ! -f "$WORK/stop" ]; do sleep 1; done
    [ -f "$WORK/stop" ] && break
    k=$((k + 1))
    [ "$k" -gt "$POOL" ] && { echo "[soak-loop] bot=$b запас предметов кончился" >>"$WORK/bot_$b.log"; break; }
    pick=$(pick_run); scen=${pick%%|*}; chaos=${pick##*|}
    # --start-slot: боты одного узла встают на разные клетки у входа (а не все в одну); у вора (бот 1) Призрак — предмет колоды, не ghost_1.
    flags="$(netem_flags "$b") --start-slot=$b"; [ "$b" -ne 1 ] && flags="$flags --no-shard"; [ "$b" -eq 1 ] && flags="$flags --ghost-daemon=it_soak_b1_${k}a"; [ -n "$chaos" ] && flags="$flags --chaos=$chaos --chaos-after=0.$((3 + RANDOM % 6))"
    # shellcheck disable=SC2086
    tmo 200 "$GODOT" --headless --path netrun -s res://tools/soak_run.gd -- --bridge="ws://127.0.0.1:$BRIDGE_PORT/netrun/v1" --key=kt \
      --runner="KEY_SOAK_B$b" --terminal="$(printf 't%02d' "$b")" --token="soak-token-$b" --items="it_soak_b${b}_${k}a,it_soak_b${b}_${k}b" \
      --host=127.0.0.1 --port="$ENET_PORT" --scenario="$scen" --tag="b$b-r$k" $flags --soak-dir="$WORK" >>"$WORK/bot_$b.log" 2>&1
    rc=$?
    echo "[soak-loop] bot=$b run=$k scenario=$scen chaos=${chaos:--} rc=$rc" >>"$WORK/bot_$b.log"
    sleep $((5 + RANDOM % 16))
  done
}
ev "боты: $BOTS"
for b in $(seq 1 "$BOTS"); do
  bot_loop "$b" &
  LOOP_PIDS+=("$!")
  sleep 0.3
done

# --- Главный цикл: наблюдение, плановые убийства, аудит ---
next_world_kill=$((SECONDS + WORLD_KILL_S))
next_bot_kill=$((SECONDS + BOT_KILL_S))
next_audit=$((SECONDS + AUDIT_S))
next_rss=$SECONDS
END=$((START + DUR))
AUDIT_MAX_ALERTS=0
audit() { # $1 — доп. аргументы; печатает итоговую строку в audit.log
  tmo 60 "$GODOT" --headless --path netrun -s res://tools/soak_audit.gd -- --bridge="ws://127.0.0.1:$BRIDGE_PORT/netrun/v1" --key=kw "$@" --soak-dir="$WORK" >"$WORK/audit.last" 2>&1
  local rc=$?
  { echo "== $((SECONDS - START)) с rc=$rc"; grep '^\[audit\]' "$WORK/audit.last"; } >>"$WORK/audit.log"
  return $rc
}
while [ $SECONDS -lt $END ]; do
  kill -0 "$BRIDGE_PID" 2>/dev/null || fail "Мост умер посреди прогона"
  if ! kill -0 "$WORLD_PID" 2>/dev/null; then
    WORLD_UNEXPECTED=$((WORLD_UNEXPECTED + 1))
    ev "СЕРВЕР МИРА №$WORLD_N УПАЛ (не по плану, ${WORLD_PID}); последние строки журнала:"
    tail -n 12 "$WORK/world_$WORLD_N.log" | tee -a "$WORK/events.log"
    touch "$WORK/world.down"; sleep 2
    start_world; rm -f "$WORK/world.down"
    ev "сервер мира №$WORLD_N поднят после падения"
  fi
  if [ $SECONDS -ge $next_rss ]; then sample_rss; next_rss=$((SECONDS + 30)); fi
  if [ $SECONDS -ge $next_world_kill ] && [ $((END - SECONDS)) -gt 45 ]; then
    ev "плановое убийство сервера мира №$WORLD_N (kill -9)"
    sample_rss
    touch "$WORK/world.down"; kill_world; WORLD_PLANNED=$((WORLD_PLANNED + 1)); sleep 3
    start_world; rm -f "$WORK/world.down"
    ev "сервер мира №$WORLD_N поднят"
    next_world_kill=$((SECONDS + WORLD_KILL_S))
  fi
  if [ $SECONDS -ge $next_bot_kill ]; then
    victim=$((1 + RANDOM % BOTS))
    if pkill -KILL -f -- "--tag=b$victim-r.*soak-dir=$WORK" 2>/dev/null; then
      BOT_KILLS=$((BOT_KILLS + 1)); ev "убит бот $victim посреди забега"
    fi
    next_bot_kill=$((SECONDS + BOT_KILL_S / 2 + RANDOM % (BOT_KILL_S + 1)))
  fi
  if [ $SECONDS -ge $next_audit ]; then
    audit; a=$(grep -o 'alerts_auditor=[0-9]*' "$WORK/audit.last" | cut -d= -f2)
    [ -n "$a" ] && [ "$a" -gt "$AUDIT_MAX_ALERTS" ] && AUDIT_MAX_ALERTS=$a && ev "тревоги аудитора: $a"
    ev "проход аудита: $(grep '^\[audit\] alerts_' "$WORK/audit.last")"
    next_audit=$((SECONDS + AUDIT_S))
  fi
  sleep 2
done

# --- Конец срока: боты доигрывают, сессии закрываются, итоговый аудит ---
ev "срок вышел: останавливаю ботов"
touch "$WORK/stop"
sample_rss
end=$((SECONDS + 100))
while [ $SECONDS -lt $end ] && pgrep -f -- "--tag=b.*soak-dir=$WORK" >/dev/null; do sleep 2; done
pkill -KILL -f -- "--tag=b.*soak-dir=$WORK" 2>/dev/null
end=$((SECONDS + 90))
open=1
while [ $SECONDS -lt $end ]; do   # открытые сессии закрывает сервер мира по окну возврата (20 с)
  audit --items="$ITEMS_EXPECTED"; arc=$?
  open=$(grep -o 'sessions_open=[0-9]*' "$WORK/audit.last" | cut -d= -f2)
  [ "${open:-1}" = 0 ] && break
  sleep 5
done
sleep 7  # аудитор Моста (период 5 с) проходит по финальному состоянию
audit --items="$ITEMS_EXPECTED"; arc=$?
cat "$WORK/audit.last" >>"$WORK/summary.txt"
sample_rss
kill -0 "$WORLD_PID" 2>/dev/null || { WORLD_UNEXPECTED=$((WORLD_UNEXPECTED + 1)); ev "сервер мира упал под конец прогона"; }

# --- Сводка ---
ALERTS_AUD=$(grep -o 'alerts_auditor=[0-9]*' "$WORK/audit.last" | cut -d= -f2); ALERTS_AUD=${ALERTS_AUD:-?}
ALERTS_OTH=$(grep -o 'alerts_other=[0-9]*' "$WORK/audit.last" | cut -d= -f2); ALERTS_OTH=${ALERTS_OTH:-?}
OPEN_END=${open:-?}
RUNS=$(cat "$WORK"/bot_*.log 2>/dev/null | grep -c '^\[soak-loop\] .* rc=')
RESULTS=$(cat "$WORK"/bot_*.log 2>/dev/null | grep -o '^\[soak-run\].* result=[^ ]*' | sed 's/.* result=//' | sort | uniq -c | awk '{printf "%s%s:%s", (NR>1?",":""), $2, $1}')
RCS=$(cat "$WORK"/bot_*.log 2>/dev/null | grep -o '^\[soak-loop\] .* rc=[0-9]*' | sed 's/.* rc=//' | sort | uniq -c | awk '{printf "%s%s:%s", (NR>1?",":""), $2, $1}')
STUCK=$(cat "$WORK"/bot_*.log 2>/dev/null | grep -c '^\[soak-run\].* result=timeout:')
UNCLOSED=$(cat "$WORK"/bot_*.log 2>/dev/null | grep -c '^\[soak-run\] .*unclosed')
ENGINE_ERR=$(cat "$WORK"/world_*.log 2>/dev/null | grep -c 'SCRIPT ERROR\|^ERROR:')
# Утечка: в экземпляре, прожившем ≥ 600 с, RSS в конце против RSS после прогрева (первый замер ≥ 120 с жизни).
RSS_INFO=$(awk -F, '
  { n=$1; t=$2; kb=$3; if (kb<=0) next; last[n]=kb; lt[n]=t; if (!(n in first)) first[n]=kb; if (t>=120 && !(n in base)) base[n]=kb }
  END { best=-1; for (n in last) if (lt[n]>best) { best=lt[n]; bn=n }
        if (bn=="") { print "n/a 0 0 0"; exit }
        b=(bn in base?base[bn]:first[bn]); l=last[bn];
        leak = (lt[bn]>=600 && (bn in base) && l>1.5*b && l-b>51200) ? 1 : 0;
        printf "%d %d %d %d", b/1024, l/1024, lt[bn], leak }' "$WORK/rss.csv" 2>/dev/null)
read -r RSS_A RSS_B RSS_T RSS_LEAK <<<"$RSS_INFO"
ELAPSED=$((SECONDS - START))
DUR_H=$(awk -v s="$ELAPSED" 'BEGIN{printf "%dч%02dм", s/3600, (s%3600)/60}')
VERDICT=PASS; WHY=""
[ "$WORLD_UNEXPECTED" -gt 0 ] && { VERDICT=FAIL; WHY="$WHY падений мира $WORLD_UNEXPECTED;"; }
[ "$ALERTS_AUD" != 0 ] && { VERDICT=FAIL; WHY="$WHY тревоги аудитора $ALERTS_AUD;"; }
[ "$arc" != 0 ] && { VERDICT=FAIL; WHY="$WHY итоговый аудит rc=$arc (предметы не сошлись или Мост молчит);"; }
[ "${OPEN_END:-1}" != 0 ] && { VERDICT=FAIL; WHY="$WHY открытых сессий в конце: $OPEN_END;"; }
[ "$RSS_LEAK" = 1 ] && { VERDICT=FAIL; WHY="$WHY утечка памяти мира;"; }
[ "$RUNS" -lt "$BOTS" ] && { VERDICT=FAIL; WHY="$WHY забегов меньше числа ботов;"; }
[ $((STUCK * 50)) -gt "$RUNS" ] && { VERDICT=FAIL; WHY="$WHY зависших ботов $STUCK из $RUNS забегов;"; }
[ "$UNCLOSED" -gt 0 ] && { VERDICT=FAIL; WHY="$WHY сессий не закрылось: $UNCLOSED;"; }
{
  echo "исходы забегов: $RESULTS"
  echo "коды выхода процессов-ботов: $RCS (137 — убит оркестратором, 4 — мир недоступен при старте)"
  echo "зависших ботов (timeout:*): $STUCK; ошибок движка в журналах мира: $ENGINE_ERR; прочих тревог Моста: $ALERTS_OTH"
  echo "плановых убийств мира: $WORLD_PLANNED, убийств ботов: $BOT_KILLS"
} >>"$WORK/summary.txt"
cat "$WORK/summary.txt"
SUMMARY_LINE="SOAK $VERDICT: ${DUR_H}, забегов $RUNS (исходы $RESULTS), падений мира $WORLD_UNEXPECTED (плановых убийств $WORLD_PLANNED, ботов убито $BOT_KILLS), RSS мира ${RSS_A}→${RSS_B} МБ за ${RSS_T} с жизни экземпляра, тревог аудитора $ALERTS_AUD,${WHY:+ причины:$WHY}"
RESULT=$VERDICT
REASON="$SUMMARY_LINE"
[ "$VERDICT" = PASS ]
