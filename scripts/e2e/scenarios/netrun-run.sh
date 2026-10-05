#!/bin/bash
# Вход в «Сеть» с настоящего телефона (M6): Alice отдаёт Мосту двух демонов (один — в защищённом слоте), бот Godot проходит узел по
# токену терминала этой сессии и выходит чисто — на телефоне шард и оба демона; во втором забеге флэтлайн (исход black_ice) —
# возвращается только защищённый демон; повтор команды с тем же rid ничего не дублирует. Мост и сервер мира — настоящие, на хосте
# (эмулятор достаёт Мост по 10.0.2.2, как коллектор); бот — отдельный процесс Godot без экрана.
# Мост запущен с --collector на коллектор стенда (секрет игры стенда — NETRUN_COLLECTOR_SECRET): в конце сценарий читает мастерский API
# коллектора и проверяет, что записи мира дошли (NET_ENTER, NET_EXIT, NET_FLATLINE, предметы), отбраковки нет, флаг нетраннера после
# флэтлайна стоит, а перезапуск Моста с той же базой и повторная отправка всей очереди не плодят записей (M6b).
# Нужны godot и Node >= 22 (на devbox godot лежит в ~/.local/bin); без godot сценарий пропускается (E2E_NETRUN_REQUIRED=1 — красный).
# Порты: E2E_NETRUN_BRIDGE (7410), E2E_NETRUN_LINE (7411, его телефон берёт из QR стойки), E2E_NETRUN_ENET (7777);
# перезапущенный Мост (проверка повтора отправки) — E2E_NETRUN_BRIDGE2 (7412) и E2E_NETRUN_LINE2 (7413): прежний порт после остановки
# держит TIME_WAIT, а WebSocket-сервер Моста не включает SO_REUSEADDR.
source "$(dirname "$0")/../lib.sh"
echo "== netrun-run"
command -v timeout >/dev/null || timeout() { shift; "$@"; }   # Mac без coreutils: пределы времени не нужны, сценарий всё равно для devbox
set -m  # у каждого фонового процесса своя группа: kill -- -PID гасит и timeout, и то, что он запустил

command -v godot >/dev/null || PATH="$HOME/.local/bin:$PATH"
if ! command -v godot >/dev/null; then
  [ "${E2E_NETRUN_REQUIRED:-0}" = 1 ] && die "нет godot в PATH (E2E_NETRUN_REQUIRED=1)"
  echo "  ПРОПУЩЕН: нет godot в PATH (на devbox — ~/.local/bin/godot)"; exit 0
fi
export PATH="${NODE_BIN:+$NODE_BIN:}$PATH"
export LC_ALL="${LC_ALL:-C.UTF-8}" LANG="${LANG:-C.UTF-8}"   # Мост без UTF-8 пишет в журнал вопросительные знаки

NR_BRIDGE=${E2E_NETRUN_BRIDGE:-7410}; NR_LINE=${E2E_NETRUN_LINE:-7411}; NR_ENET=${E2E_NETRUN_ENET:-7777}
NR_BRIDGE2=${E2E_NETRUN_BRIDGE2:-7412}; NR_LINE2=${E2E_NETRUN_LINE2:-7413}
NR_DIR="$E2E_DIR/netrun"; rm -rf "$NR_DIR"; mkdir -p "$NR_DIR"
export NETRUN_KEY_WORLD=kw NETRUN_KEY_MASTER=km NETRUN_KEY_TEST=kt   # ключи ролей — только для этого прогона
TOKEN="e2e-token-t03"; NODE_ID=node_07; TERM_ID=t03
PKA=$(cat "$E2E_DIR/pk_$A.txt")
PIDS=(); PA=""
nr_cleanup() {
  local p; for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill -KILL -- "-$p" 2>/dev/null; done
  [ -n "$PA" ] && adb_ $A emu redir del tcp:$PA >/dev/null 2>&1
  wait 2>/dev/null
  # Баннер «Подключено» на Кибердеке гаснет сам по добыче Моста или через 2 часа; не ждём и закрываем сразу, иначе он мешает UI-сценариям после этого (sec-alert, slot-race)
  dbg $A DEBUG_SET --es netrun dismiss
}
trap nr_cleanup EXIT
nr_save_logs() { mkdir -p "$E2E_DIR/journals"; for f in "$NR_DIR"/*.log; do [ -f "$f" ] && cp "$f" "$E2E_DIR/journals/netrun-$(basename "$f")"; done; }
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
for p in $NR_BRIDGE $NR_LINE $NR_ENET $NR_BRIDGE2 $NR_LINE2; do ! port_open $p || die "порт $p занят (остался процесс прошлого прогона?)"; done

# ── запрос к Мосту ролью test: nrj '<json>' печатает ответ; nrp '<json>' '<python-выражение от d>' — поле ответа ──
nrj() { node "$ROOT/scripts/e2e/netrun-bridge.mjs" $NR_BRIDGE kt "$1"; }
nrp() { nrj "$1" | python3 -c "import sys,json;d=json.load(sys.stdin);print($2)"; }
item_owner() { nrp "{\"op\":\"get\",\"type\":\"item\",\"id\":\"$1\"}" 'd["doc"]["data"]["owner"]'; }
session_view() { nrp "{\"op\":\"get\",\"type\":\"session\",\"id\":\"$1\"}" 'd["doc"]["data"]["state"]+"/"+str(d["doc"]["data"].get("outcome"))'; }
# последняя не закрытая сессия Alice (id) — после MB10ENTERED она в pending
open_session() { nrp '{"op":"list","type":"session"}' "next((s['id'] for s in d['docs'] if s['data'].get('runner')=='$PKA' and s['data'].get('state')!='closed'),'')"; }
# предмет деки сессии $1 с эффектом $2 (id документа item)
deck_item() { nrp '{"op":"list","type":"item"}' "next((i['id'] for i in d['docs'] if i['data'].get('owner')=='deck:$1' and (i['data'].get('daemon') or {}).get('effect')=='$2'),'')"; }
phone_has() { q $A "select count(*) from $1 where id='$2'"; }
items_total() { nrp '{"op":"list","type":"item"}' 'len(d["docs"])'; }
entered_started() { journal_cat $A | grep -c 'netrun.enter_start'; }
world_accepted() { journal_cat $A | grep -c 'netrun.world_item .*accepted=true'; }   # карточки Мосту принятые телефоном без «Принять»
entered_ok() { journal_cat $A | grep -c 'netrun.entered rid=.* ok=true'; }

# ── Записи мира у коллектора (M6b): мастерский API коллектора стенда (api GET …) и журнал самого Моста ──
# col_recs '<python-выражение от recs>' — recs: записи мира, принятые коллектором от ключа этого Моста (GET /api/events?kind=net); в r['nv'] — разобранный newValue
col_recs() {
  api GET "/api/events?kind=net&pageSize=200" | python3 -c "
import sys, json
d = json.load(sys.stdin)
recs = [dict(r, nv=json.loads(r['new_value'] or '{}')) for r in d['records'] if r['subject_key'] == '$WORLD_PUB']
print($1)"
}
col_total() { col_recs 'len(recs)'; }
col_count() { col_recs "len([r for r in recs if r['reason'] == '$1' and r['source_ref'] == '$2'])"; }                  # col_count <причина> <sourceRef>
col_field() { col_recs "next((r['nv'].get('$3') for r in recs if r['reason'] == '$1' and r['source_ref'] == '$2'), 'нет записи')"; }   # col_field <причина> <sourceRef> <поле newValue>
# col_flag '<python-выражение от f>' — флаг допуска Alice у коллектора (GET /api/net/runners); флага нет — «нет флага»
col_flag() {
  api GET /api/net/runners | python3 -c "
import sys, json
n = lambda k: k.replace('-', '+').replace('_', '/').rstrip('=')
f = next((f for f in json.load(sys.stdin) if n(f['runnerKey']) == n('$PKA')), None)
print($1 if f else 'нет флага')"
}
# sync_sum <журнал Моста> <sent|accepted|rejected> — сумма поля по строкам «WorldSync sync.ok …» (каждая отправка на коллектор, в том числе пустая)
sync_sum() { grep -h 'WorldSync sync.ok ' "$1" 2>/dev/null | sed -n "s/.* $2=\([0-9][0-9]*\).*/\1/p" | awk '{s+=$1} END{print s+0}'; }
# enqueued <журнал Моста…> — сколько записей мира Мост поставил в очередь (строки «record.enqueued»)
enqueued() { cat "$@" 2>/dev/null | grep -c 'record.enqueued'; }
# «same», если коллектор принял ровно столько записей мира, сколько Мост поставил в очередь (журналы — аргументы); иначе оба числа
col_vs_bridge() { local c b; c=$(col_total); b=$(enqueued "$@"); [ "$c" = "$b" ] && echo same || echo "у коллектора $c, Мост поставил $b"; }
# «same», если Мост получил подтверждение (accepted) на каждую поставленную в очередь запись
bridge_acked() { local a b; a=$(sync_sum "$1" accepted); b=$(enqueued "$1"); [ "$a" = "$b" ] && echo same || echo "подтверждено $a, поставлено $b"; }

# ── 1. Alice: два демона для деки ──
# Стартовый Datamine засевается при первом открытии Кибердеки, и только в пустую коллекцию (DaemonStore.ensureSeeded): выданные до этого
# демоны оставили бы Alice без Datamine, и UI-сценарии взлома после нас (sec-alert, slot-race) не нашли бы его на экране.
open_deck $A
eq_wait 30 "у Alice засеян стартовый Datamine" 1 phone_has daemons datamine_v1
dbg $A DEBUG_SET --es daemon "NRghost:1C,55:1:GHOST"
dbg $A DEBUG_SET --es daemon "NRjitter:1C,E9:1:JITTER"
D_GHOST="debug-NRghost"; D_JITTER="debug-NRjitter"
eq_wait 20 "у Alice есть демон GHOST" 1 phone_has daemons "$D_GHOST"
eq_wait 20 "у Alice есть демон JITTER" 1 phone_has daemons "$D_JITTER"

# ── 2. Мост со стендовыми данными: узел, терминал с токеном, Alice (обучение пройдено), два шарда в узле ──
python3 - "$PKA" "$TOKEN" "$NODE_ID" "$TERM_ID" > "$NR_DIR/seed.json" <<'PY'
import sys, json, hashlib, base64
pk, token, node, term = sys.argv[1:5]
sha = lambda x: hashlib.sha256(x.encode()).hexdigest()
b64 = lambda x: base64.b64encode(x.encode()).decode()
def item(owner, payload, kind):
    return {"owner": owner, "kind": kind, "payload": payload, "protected": False, "origin": "node:" + node,
            "in_transfer": None, "out_transfer": None, "handover": None}
def shard(i, title): return "|".join(["SHARD", i, "0", "1", b64("e2e"), b64(title), b64("meta"), b64("тело"), "0", "1"])
print(json.dumps({
    "settings": {"global": {"auditor_period_s": 3}},
    "node": {node: {"title": "Серый узел", "tier": "STANDARD", "tutorial": False, "lockdown_until": 0, "eddies": 0}},
    "terminal": {term: {"node": node, "label": "стенд e2e", "token_sha256": sha(token), "silent": False}},
    "runner": {"r_" + sha(pk)[:32]: {"key": pk, "callsign": "Alice", "blocked": False, "runs": 1, "tutorial_done": True}},
    "item": {"it_nr_shard_1": item("node:" + node, shard("nr-shard-1", "Шард e2e 1"), "SHARD"),
             "it_nr_shard_2": item("node:" + node, shard("nr-shard-2", "Шард e2e 2"), "SHARD")},
}, ensure_ascii=False))
PY
if [ ! -x "$ROOT/netrun-bridge/build/install/netrun-bridge/bin/netrun-bridge" ] || [ -n "$(find "$ROOT/netrun-bridge/src" "$ROOT/kit/src" -newer "$ROOT/netrun-bridge/build/install/netrun-bridge/lib" -type f 2>/dev/null | head -1)" ]; then
  log "сборка Моста…"; (cd "$ROOT" && timeout 600 ./gradlew -q :netrun-bridge:installDist) > "$NR_DIR/gradle.log" 2>&1 || { tail -20 "$NR_DIR/gradle.log"; die "не собрался Мост"; }
fi
# Импорт каждый раз: старый кеш .godot не знает новых class_name, и main.gd не компилируется (журнал devbox: «FlatlineAudio not declared»).
log "импорт проекта Godot…"; timeout 240 godot --headless --path "$ROOT/netrun" --import > "$NR_DIR/import.log" 2>&1
# ── 4. Мост ↔ эмулятор: адрес телефона Мост по строкам не узнает (эмулятор за NAT виден ему как 127.0.0.1, а такой адрес kit
#      пропускает), поэтому порт приложения пробрасывается на хост под тем же номером (как link.sh для пиров), а Мост получает
#      статическую запись `--phone 127.0.0.1:порт=ключ Alice` ──
PA=$(await 30 port_of $A); [ -n "$PA" ] || { nr_save_logs; die "порт приложения Alice не найден"; }
adb_ $A emu redir add tcp:$PA:$PA >/dev/null || die "emu redir tcp:$PA не добавился (порт занят на хосте?)"
# Записи мира уходят на коллектор стенда: Мост на хосте, поэтому 127.0.0.1, а не 10.0.2.2. Секрет игры стенда (если стенд поднят с
# E2E_GAME_SECRET) — только в окружении Моста; пустой Мост считает отсутствующим.
COLLECTOR_URL="http://127.0.0.1:$PORT"
NETRUN_COLLECTOR_SECRET="${E2E_GAME_SECRET:-}" timeout 1200 "$ROOT/netrun-bridge/build/install/netrun-bridge/bin/netrun-bridge" --port $NR_BRIDGE --line-port $NR_LINE \
  --db "$NR_DIR/bridge.db" --test --seed "$NR_DIR/seed.json" --phone "127.0.0.1:$PA=$PKA" --collector "$COLLECTOR_URL" > "$NR_DIR/bridge.log" 2>&1 &
BRIDGE=$!; PIDS+=($BRIDGE)
check "Мост поднялся" wait_until 60 port_open $NR_BRIDGE
WORLD_PUB=$(node "$ROOT/scripts/e2e/netrun-bridge.mjs" $NR_BRIDGE kt hello | python3 -c "import sys,json;print(json.load(sys.stdin)['world_pub'])")
[ -n "$WORLD_PUB" ] || { nr_save_logs; die "Мост не отдал ключ мира"; }

# ── 3. Сервер мира на настоящем Мосте ──
# Сценарий про возврат добычи на телефон, а не про взлом хранилища (К3): бот без EXTRACT_SHARD берёт шард без открытия, поэтому флаг выключен.
timeout 1200 godot --headless --path "$ROOT/netrun" -- --bridge="ws://127.0.0.1:$NR_BRIDGE" --bridge-key=kw --port=$NR_ENET --grace=20 --vault-requires-open=false > "$NR_DIR/world.log" 2>&1 &
PIDS+=($!)
check "сервер мира получил снимок Моста" wait_until 120 grep -q "снимок Моста" "$NR_DIR/world.log"

RACK="MB10:RACK:v1:$TERM_ID:$(printf %s "10.0.2.2:$NR_LINE" | base64 | tr -d '\n'):$WORLD_PUB:$(printf %s "стенд e2e" | base64 | tr -d '\n')"

enter() { # enter <сколько входов уже было>: Alice сдаёт обоих демонов, защищённый — JITTER; ждём подписанный MB10ENTERED
  dbg $A DEBUG_SET --es netrun "$RACK|$D_GHOST,$D_JITTER|$D_JITTER"
  eq_wait 30 "вход №$1: телефон начал вход (netrun.enter_start)" "$1" entered_started
  eq_wait 90 "вход №$1: Мост ответил телефону ok=true (MB10ENTERED)" "$1" entered_ok
  eq_wait 20 "вход №$1: сданные демоны ушли с телефона" 0 phone_has daemons "$D_GHOST"
}

# ── 5. Забег 1: чистый выход, добыча и демоны возвращаются ──
adb_ $A logcat -c
enter 1
S1=$(await 20 open_session); [ -n "$S1" ] || { nr_save_logs; die "у Моста нет сессии Alice"; }
eq "сессия 1 ждёт курка (pending)" "pending/None" "$(session_view $S1)"
eq "обе карточки приняты Мостом: демоны в деке сессии 1" "2" "$(nrp '{"op":"list","type":"item"}' "len([i for i in d['docs'] if i['data'].get('owner')=='deck:$S1'])")"
check "терминал подтвердил сессию (session.confirm, курок очков — позже)" bash -c "node '$ROOT/scripts/e2e/netrun-bridge.mjs' $NR_BRIDGE kt '{\"op\":\"session.confirm\",\"session\":\"$S1\",\"terminal\":\"$TERM_ID\"}' | grep -q '\"ok\":true'"
GH1=$(deck_item $S1 GHOST); [ -n "$GH1" ] || { nr_save_logs; die "в деке сессии нет GHOST"; }
timeout 240 godot --headless --path "$ROOT/netrun" -- --bot=ghost_run --bot-daemon="$GH1" --host=127.0.0.1 --port=$NR_ENET \
  --token="$TERM_ID:$TOKEN" --exit-after=200 > "$NR_DIR/bot.log" 2>&1 &
BOT=$!; PIDS+=($BOT)
check "бот вышел чисто и взял шард" wait_until 220 bash -c "grep -q '\[bot\] итог: clean' '$NR_DIR/bot.log'"
eq_wait 90 "Мост закрыл сессию 1 чисто" "closed/clean" session_view "$S1"
eq_wait 90 "шард взят и вернулся на телефон" 1 phone_has shards nr-shard-1
eq_wait 60 "демон GHOST вернулся на телефон" 1 phone_has daemons "$D_GHOST"
eq_wait 60 "демон JITTER вернулся на телефон" 1 phone_has daemons "$D_JITTER"
eq_wait 30 "добыча и демоны приняты телефоном без «Принять» (3 карточки Моста)" 3 world_accepted
eq "шард 1 у Alice в Мосте" "phone:$PKA" "$(item_owner it_nr_shard_1)"
eq "шард 2 остался в узле" "node:$NODE_ID" "$(item_owner it_nr_shard_2)"

# ── 6. Забег 2: флэтлайн. Исход black_ice сервер мира сам не выдаёт без ICE и trace 100 — закрываем забег тестовым путём Моста
#      (роль test делает то же, что сервер мира: take + run.finish) ──
enter 2
S2=$(await 20 open_session); [ -n "$S2" ] || { nr_save_logs; die "у Моста нет второй сессии Alice"; }
[ "$S2" != "$S1" ] || die "вторая сессия совпала с первой"
nrj "{\"op\":\"session.confirm\",\"session\":\"$S2\",\"terminal\":\"$TERM_ID\"}" >/dev/null
GH2=$(deck_item $S2 GHOST)
TAKE="{\"op\":\"op.take_from_node\",\"rid\":\"e2e-take-2\",\"session\":\"$S2\",\"node\":\"$NODE_ID\",\"item\":\"it_nr_shard_2\"}"
FIN="{\"op\":\"run.finish\",\"rid\":\"e2e-finish-2\",\"session\":\"$S2\",\"outcome\":\"black_ice\",\"node\":\"$NODE_ID\",\"disconnect\":false,\"moves\":[{\"item\":\"$GH2\",\"to\":\"node\"},{\"item\":\"it_nr_shard_2\",\"to\":\"node\"}]}"
eq "шард 2 взят в деку" "True" "$(nrp "$TAKE" 'd["ok"] and not d["replayed"]')"
eq "run.finish black_ice принят" "True" "$(nrp "$FIN" 'd["ok"] and not d["replayed"]')"
eq "сессия 2 закрыта black_ice" "closed/black_ice" "$(session_view $S2)"
# свидетельство, что выдача после флэтлайна отработала: защищённый демон вернулся — только после этого проверяем, что остального нет
eq_wait 90 "флэтлайн: защищённый демон JITTER вернулся на телефон" 1 phone_has daemons "$D_JITTER"
eq_wait 20 "флэтлайн: телефон принял от Моста ещё одну карточку (защищённого демона)" 4 world_accepted
eq "флэтлайн: GHOST на телефон не вернулся" 0 "$(phone_has daemons "$D_GHOST")"
eq "флэтлайн: GHOST остался в узле (мёртвая дека)" "node:$NODE_ID" "$(item_owner "$GH2")"
eq "флэтлайн: добыча (шард 2) осталась в узле" "node:$NODE_ID" "$(item_owner it_nr_shard_2)"
eq "флэтлайн: шарда 2 на телефоне нет" 0 "$(phone_has shards nr-shard-2)"
eq "флэтлайн: шард 1 с прошлого забега на месте" 1 "$(phone_has shards nr-shard-1)"
eq "нетраннер заблокирован Мостом" "True" "$(nrp '{"op":"list","type":"runner"}' "[r for r in d['docs'] if r['data'].get('key')=='$PKA'][0]['data'].get('blocked')")"
eq "Мост поднял тревогу «ФЛЭТЛАЙН» (ровно одну)" "flatline" "$(nrp '{"op":"list","type":"alert"}' "','.join(a['data']['kind'] for a in d['docs'])")"
# Записи мира у коллектора — раздел 8 (после повторов команд, чтобы он заодно показал, что повторы записей не родили).

# ── 7. Повтор команд с тем же rid: ничего не дублируется ──
ITEMS_BEFORE=$(items_total)
eq "повтор take с тем же rid не выполняется второй раз" "True" "$(nrp "$TAKE" 'd["ok"] and d["replayed"]')"
eq "повтор run.finish с тем же rid не выполняется второй раз" "True" "$(nrp "$FIN" 'd["ok"] and d["replayed"]')"
eq "после повторов шард 2 всё ещё в узле, а не раздвоился" "node:$NODE_ID" "$(item_owner it_nr_shard_2)"
eq "документов item в Мосте столько же (повтор не создал предмет)" "$ITEMS_BEFORE" "$(items_total)"
eq "после повторов у Alice по-прежнему один JITTER" 1 "$(phone_has daemons "$D_JITTER")"
eq "после повторов у Alice по-прежнему один шард 1" 1 "$(phone_has shards nr-shard-1)"
check "бот и сервер мира без ошибок движка" bash -c "! grep -q 'SCRIPT ERROR' '$NR_DIR/world.log' '$NR_DIR/bot.log'"

# ── 8. Записи мира дошли до коллектора (M6b) ──
# Мост ставит запись в очередь в транзакции документов и шлёт её сразу после коммита (SyncEngine); коллектор принимает её тем же приёмом
# /api/changes, что и записи телефонов, и показывает в журнале событий (kind=net). Доставка асинхронна — везде eq_wait.
eq_wait 90 "коллектор принял NET_ENTER сессии 1" 1 col_count NET_ENTER "$S1"
eq_wait 30 "коллектор принял NET_ENTER сессии 2" 1 col_count NET_ENTER "$S2"
eq_wait 30 "коллектор принял NET_EXIT сессии 1 (чистый выход)" 1 col_count NET_EXIT "$S1"
eq_wait 30 "коллектор принял NET_FLATLINE сессии 2 (флэтлайн)" 1 col_count NET_FLATLINE "$S2"
# Все записи, которые Мост поставил в очередь, у коллектора, и отбраковки нет: kit удаляет отвергнутое из очереди молча, поэтому «rejected=0»
# доказывается двояко — по ответам коллектора в журнале Моста и по тому, что у коллектора записей ровно столько, сколько поставил Мост.
eq_wait 60 "коллектор принял все записи мира, которые Мост поставил в очередь" same col_vs_bridge "$NR_DIR/bridge.log"
eq_wait 30 "Мост получил подтверждение коллектора на каждую свою запись (accepted)" same bridge_acked "$NR_DIR/bridge.log"
eq "коллектор не отбраковал ни одной записи Моста (rejected=0 во всех ответах)" 0 "$(sync_sum "$NR_DIR/bridge.log" rejected)"
eq "в журнале Моста нет отказов и ошибок отправки (sync.rejected, sync.http_error, world.derive_failed)" 0 "$(grep -cE 'sync\.rejected|sync\.http_error|sync\.bad_|world\.derive_failed' "$NR_DIR/bridge.log")"
eq "NET_EXIT и NET_FLATLINE взаимоисключающи: у флэтлайна сессии 2 нет NET_EXIT" 0 "$(col_count NET_EXIT "$S2")"
eq "NET_EXIT и NET_FLATLINE взаимоисключающи: у чистого выхода сессии 1 нет NET_FLATLINE" 0 "$(col_count NET_FLATLINE "$S1")"
eq "NET_ENTER 1: нетраннер — Alice" "$PKA" "$(col_field NET_ENTER "$S1" runner)"
eq "NET_ENTER 1: терминал" "$TERM_ID" "$(col_field NET_ENTER "$S1" terminal)"
eq "NET_ENTER 1: узел" "$NODE_ID" "$(col_field NET_ENTER "$S1" node)"
eq "NET_ENTER 1: сдано два демона" 2 "$(col_field NET_ENTER "$S1" deck)"
eq "NET_ENTER 1: среди них защищённый" True "$(col_field NET_ENTER "$S1" protected)"
eq "NET_EXIT 1: исход clean" clean "$(col_field NET_EXIT "$S1" outcome)"
eq "NET_EXIT 1: нетраннер — Alice" "$PKA" "$(col_field NET_EXIT "$S1" runner)"
eq "NET_EXIT 1: вернулось 3 предмета (шард и оба демона, как на телефоне)" 3 "$(col_field NET_EXIT "$S1" returned)"
eq "NET_FLATLINE 2: нетраннер — Alice" "$PKA" "$(col_field NET_FLATLINE "$S2" runner)"
eq "NET_FLATLINE 2: терминал" "$TERM_ID" "$(col_field NET_FLATLINE "$S2" terminal)"
eq "NET_FLATLINE 2: узел" "$NODE_ID" "$(col_field NET_FLATLINE "$S2" node)"
eq "NET_FLATLINE 2: исход black_ice" black_ice "$(col_field NET_FLATLINE "$S2" outcome)"
eq "NET_FLATLINE 2: не обрыв связи" False "$(col_field NET_FLATLINE "$S2" disconnect)"
eq "NET_FLATLINE 2: в узле осталось 2 предмета (мёртвая дека GHOST и добыча)" 2 "$(col_field NET_FLATLINE "$S2" left_in_node)"
eq "NET_FLATLINE 2: ссылается на тревогу «ФЛЭТЛАЙН» Моста" "$(nrp '{"op":"list","type":"alert"}' "d['docs'][0]['id']")" "$(col_field NET_FLATLINE "$S2" alert)"
# Шард 2 за сценарий менял владельца дважды (узел → дека при take, дека → узел при run.finish); повторы take/run.finish из раздела 7 записей не добавили
eq "NET_ITEM_OWNER: шард 2 сменил владельца ровно дважды, повторы команд записей не родили" 2 "$(col_count NET_ITEM_OWNER it_nr_shard_2)"
# Флаг нетраннера (решение владельца: источник правды — коллектор, netrun-world-records.md, п. 5.4): после флэтлайна Alice заблокирована
eq_wait 30 "у коллектора нетраннер Alice заблокирован после флэтлайна" True col_flag "f['blocked']"
eq "флаг у коллектора: сессия флэтлайна" "$S2" "$(col_flag "f['session']")"
eq "флаг у коллектора: узел" "$NODE_ID" "$(col_flag "f['node']")"
eq "флаг у коллектора: терминал" "$TERM_ID" "$(col_flag "f['terminal']")"
eq "флаг у коллектора: причина" "флэтлайн" "$(col_flag "f['reason']")"
eq "флаг у коллектора: Alice — известный коллектору игрок" True "$(col_flag "f['knownPlayer']")"

# ── 9. Повтор отправки: перезапуск Моста с той же базой ──
# Обычный перезапуск ничего не отправит заново: подтверждённые записи лежат в журнале Моста (accepted_at) и в очередь не возвращаются.
# Чтобы воспроизвести настоящую повторную отправку (коллектор принял записи, а подтверждение до Моста не дошло и markAccepted не записал),
# у остановленного Моста строкам таблицы world_records снимается accepted_at — после старта он шлёт всю очередь второй раз с теми же id и seq.
REC_N=$(col_total); BLOCKED_AT=$(col_flag "f['blockedAt']")
[ "${REC_N:-0}" -gt 0 ] 2>/dev/null || { nr_save_logs; die "у коллектора нет записей мира перед перезапуском Моста (REC_N=${REC_N:-пусто})"; }
kill -TERM -- "-$BRIDGE" 2>/dev/null
check "Мост остановлен" wait_until 30 bash -c "! kill -0 -- -$BRIDGE 2>/dev/null"
kill -KILL -- "-$BRIDGE" 2>/dev/null   # завис в завершении — добиваем; процесса уже нет — ничего не делает
eq "после остановки в очереди Моста все записи снова неотправленные (accepted_at снят)" "$REC_N" "$(sqlite3 -batch -noheader "$NR_DIR/bridge.db" "UPDATE world_records SET accepted_at=NULL; SELECT COUNT(*) FROM world_records WHERE accepted_at IS NULL;")"
NETRUN_COLLECTOR_SECRET="${E2E_GAME_SECRET:-}" timeout 600 "$ROOT/netrun-bridge/build/install/netrun-bridge/bin/netrun-bridge" --port $NR_BRIDGE2 --line-port $NR_LINE2 \
  --db "$NR_DIR/bridge.db" --test --collector "$COLLECTOR_URL" > "$NR_DIR/bridge2.log" 2>&1 &
PIDS+=($!)
check "Мост поднялся заново на той же базе" wait_until 60 port_open $NR_BRIDGE2
eq "тот же ключ мира, что до перезапуска (база и файл ключа те же)" "$WORLD_PUB" "$(node "$ROOT/scripts/e2e/netrun-bridge.mjs" $NR_BRIDGE2 kt hello | python3 -c "import sys,json;print(json.load(sys.stdin)['world_pub'])")"
resent() { local a; a=$(sync_sum "$NR_DIR/bridge2.log" accepted); [ "$a" -ge "$REC_N" ] 2>/dev/null && echo done || echo "подтверждено ${a:-0} из $REC_N"; }
eq_wait 90 "перезапущенный Мост заново отправил всю очередь, и коллектор подтвердил каждую запись" done resent
eq "повторная отправка: коллектор не отбраковал ни одной записи" 0 "$(sync_sum "$NR_DIR/bridge2.log" rejected)"
eq "в журнале перезапущенного Моста нет отказов отправки" 0 "$(grep -cE 'sync\.rejected|sync\.http_error|sync\.bad_|world\.derive_failed' "$NR_DIR/bridge2.log")"
eq_wait 30 "повторная отправка не плодит записи: у коллектора столько же, плюс только поставленное Мостом после перезапуска" same col_vs_bridge "$NR_DIR/bridge.log" "$NR_DIR/bridge2.log"
eq "повторная отправка не затронула флаг нетраннера (блокировка не переставлена заново)" "$BLOCKED_AT" "$(col_flag "f['blockedAt']")"
eq "флаг нетраннера по-прежнему стоит" True "$(col_flag "f['blocked']")"

[ $FAILED -eq 0 ] || nr_save_logs
finish
