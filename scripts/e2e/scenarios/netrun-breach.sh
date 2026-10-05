#!/bin/bash
# «Сеть» с НАСТОЯЩИМ взломом хранилища (Х2): сервер мира запущен с настоящим Мостом БЕЗ флага --vault-requires-open=false — шард в
# хранилище закрыт, пока его не взломали. Alice сдаёт Мосту трёх демонов (GHOST, EXTRACT_SHARD с цепочкой, защищённый JITTER), бот Godot
# (демон EXTRACT_SHARD) прячется GHOST-ом, взламывает хранилище автосолвером по сетке, берёт шард, отправляет его (give, К5б) контакту
# телефона — Bob — и выходит чисто. Проверяется то, что записывает Мост: run.breach (исход, эдди из запаса узла, открытое хранилище,
# остывание узла у нетраннера), шард ушёл из деки в outbox Bob (на телефон Alice не вернулся), чистый выход (демоны и эдди — Alice),
# записи мира у коллектора (две смены владельца шарда, вторая — give_item). Второй забег Alice: хранилище пополнено вторым шардом,
# но узел для неё остывает — взлом отказывает (cooldown) и на сервере мира, и в Мосте, шард остаётся в узле, выход снова чистый.
# Смысл netrun-run.sh (мир БЕЗ обязательного взлома: возврат добычи, флэтлайн, повтор отправки) этот сценарий не меняет.
# Нужны godot и Node >= 22 (на devbox godot лежит в ~/.local/bin); без godot сценарий пропускается (E2E_NETRUN_REQUIRED=1 — красный).
# Порты свои (netrun-run держит 7410/7411/7777 в TIME_WAIT после остановки Моста): E2E_NRB_BRIDGE (7414), E2E_NRB_LINE (7415, его телефон
# берёт из QR стойки), E2E_NRB_ENET (7778).
source "$(dirname "$0")/../lib.sh"
echo "== netrun-breach"
command -v timeout >/dev/null || timeout() { shift; "$@"; }   # Mac без coreutils: пределы времени не нужны, сценарий всё равно для devbox
set -m  # у каждого фонового процесса своя группа: kill -- -PID гасит и timeout, и то, что он запустил

command -v godot >/dev/null || PATH="$HOME/.local/bin:$PATH"
if ! command -v godot >/dev/null; then
  [ "${E2E_NETRUN_REQUIRED:-0}" = 1 ] && die "нет godot в PATH (E2E_NETRUN_REQUIRED=1)"
  echo "  ПРОПУЩЕН: нет godot в PATH (на devbox — ~/.local/bin/godot)"; exit 0
fi
export PATH="${NODE_BIN:+$NODE_BIN:}$PATH"
export LC_ALL="${LC_ALL:-C.UTF-8}" LANG="${LANG:-C.UTF-8}"   # Мост без UTF-8 пишет в журнал вопросительные знаки

NR_BRIDGE=${E2E_NRB_BRIDGE:-7414}; NR_LINE=${E2E_NRB_LINE:-7415}; NR_ENET=${E2E_NRB_ENET:-7778}
NR_DIR="$E2E_DIR/netrun-breach"; rm -rf "$NR_DIR"; mkdir -p "$NR_DIR"
export NETRUN_KEY_WORLD=kw NETRUN_KEY_MASTER=km NETRUN_KEY_TEST=kt   # ключи ролей — только для этого прогона
TOKEN="e2e-token-t03"; NODE_ID=node_07; TERM_ID=t03; NODE_EDDIES=40
PKA=$(cat "$E2E_DIR/pk_$A.txt"); PKB=$(cat "$E2E_DIR/pk_$B.txt")
[ -n "$PKA" ] && [ -n "$PKB" ] || die "нет ключей Alice/Bob в $E2E_DIR (стенд поднят up.sh?)"
PIDS=(); PA=""
nr_cleanup() {
  local p; for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill -KILL -- "-$p" 2>/dev/null; done
  [ -n "$PA" ] && adb_ $A emu redir del tcp:$PA >/dev/null 2>&1
  wait 2>/dev/null
  # Баннер «Подключено» на Кибердеке гаснет сам по добыче Моста или через 2 часа; закрываем сразу, иначе он мешает UI-сценариям после этого
  dbg $A DEBUG_SET --es netrun dismiss
}
trap nr_cleanup EXIT
nr_save_logs() { mkdir -p "$E2E_DIR/journals"; for f in "$NR_DIR"/*.log; do [ -f "$f" ] && cp "$f" "$E2E_DIR/journals/netrun-breach-$(basename "$f")"; done; }
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
for p in $NR_BRIDGE $NR_LINE $NR_ENET; do ! port_open $p || die "порт $p занят (остался процесс прошлого прогона?)"; done

# ── запрос к Мосту ролью test: nrj '<json>' печатает ответ; nrp '<json>' '<python-выражение от d>' — поле ответа ──
nrj() { node "$ROOT/scripts/e2e/netrun-bridge.mjs" $NR_BRIDGE kt "$1"; }
nrp() { nrj "$1" | python3 -c "import sys,json;d=json.load(sys.stdin);print($2)"; }
item_owner() { nrp "{\"op\":\"get\",\"type\":\"item\",\"id\":\"$1\"}" 'd["doc"]["data"]["owner"]'; }
session_view() { nrp "{\"op\":\"get\",\"type\":\"session\",\"id\":\"$1\"}" 'd["doc"]["data"]["state"]+"/"+str(d["doc"]["data"].get("outcome"))'; }
# поле документа: doc_field <тип> <id> '<python-выражение от data>'
doc_field() { nrp "{\"op\":\"get\",\"type\":\"$1\",\"id\":\"$2\"}" "(lambda data: $3)(d['doc']['data'])"; }
# последняя не закрытая сессия Alice (id) — после MB10ENTERED она в pending
open_session() { nrp '{"op":"list","type":"session"}' "next((s['id'] for s in d['docs'] if s['data'].get('runner')=='$PKA' and s['data'].get('state')!='closed'),'')"; }
# предмет деки сессии $1 с эффектом $2 (id документа item)
deck_item() { nrp '{"op":"list","type":"item"}' "next((i['id'] for i in d['docs'] if i['data'].get('owner')=='deck:$1' and (i['data'].get('daemon') or {}).get('effect')=='$2'),'')"; }
phone_has() { q $A "select count(*) from $1 where id='$2'"; }
# Журнал телефона копится между сценариями (netrun-run идёт позже, но порядок не должен иметь значения): считаем строки сверх тех, что были при старте.
J0_START=0; J0_OK=0
entered_started() { echo $(( $(journal_cat $A | grep -c 'netrun.enter_start') - J0_START )); }
entered_ok() { echo $(( $(journal_cat $A | grep -c 'netrun.entered rid=.* ok=true') - J0_OK )); }
J0_START=$(entered_started); J0_OK=$(entered_ok)
bot_said() { grep -q "$1" "$NR_DIR/$2.log"; }   # bot_said '<regexp>' <имя журнала бота>

# ── Записи мира у коллектора: мастерский API коллектора стенда (api GET …) ──
# col_recs '<python-выражение от recs>' — recs: записи мира от ключа этого Моста (GET /api/events?kind=net); в r['nv'] — разобранный newValue
col_recs() {
  api GET "/api/events?kind=net&pageSize=200" | python3 -c "
import sys, json
d = json.load(sys.stdin)
recs = [dict(r, nv=json.loads(r['new_value'] or '{}')) for r in d['records'] if r['subject_key'] == '$WORLD_PUB']
print($1)"
}
col_count() { col_recs "len([r for r in recs if r['reason'] == '$1' and r['source_ref'] == '$2'])"; }                  # col_count <причина> <sourceRef>
col_field() { col_recs "next((r['nv'].get('$3') for r in recs if r['reason'] == '$1' and r['source_ref'] == '$2'), 'нет записи')"; }   # col_field <причина> <sourceRef> <поле newValue>
# запись о смене владельца предмета $1 с операцией $2 — поле $3
item_rec() { col_recs "next((r['nv'].get('$3') for r in recs if r['reason'] == 'NET_ITEM_OWNER' and r['source_ref'] == '$1' and r['nv'].get('op') == '$2'), 'нет записи')"; }

# ── 1. Alice: три демона для деки ──
# Стартовый Datamine засевается при первом открытии Кибердеки, и только в пустую коллекцию: выданные до этого демоны оставили бы Alice без
# Datamine, и UI-сценарии взлома после нас (sec-alert, slot-race) не нашли бы его на экране.
open_deck $A
eq_wait 30 "у Alice засеян стартовый Datamine" 1 phone_has daemons datamine_v1
dbg $A DEBUG_SET --es daemon "NRghost:1C,55:1:GHOST"
dbg $A DEBUG_SET --es daemon "NRextract:55,FF:1:EXTRACT_SHARD"
dbg $A DEBUG_SET --es daemon "NRjitter:1C,E9:1:JITTER"
D_GHOST="debug-NRghost"; D_EXTRACT="debug-NRextract"; D_JITTER="debug-NRjitter"
eq_wait 20 "у Alice есть демон GHOST" 1 phone_has daemons "$D_GHOST"
eq_wait 20 "у Alice есть демон EXTRACT_SHARD" 1 phone_has daemons "$D_EXTRACT"
eq_wait 20 "у Alice есть демон JITTER" 1 phone_has daemons "$D_JITTER"

# ── 2. Мост со стендовыми данными: узел с запасом эдди, терминал с токеном, Alice (обучение пройдено), два шарда в узле ──
python3 - "$PKA" "$TOKEN" "$NODE_ID" "$TERM_ID" "$NODE_EDDIES" > "$NR_DIR/seed.json" <<'PY'
import sys, json, hashlib, base64
pk, token, node, term, eddies = sys.argv[1:6]
sha = lambda x: hashlib.sha256(x.encode()).hexdigest()
b64 = lambda x: base64.b64encode(x.encode()).decode()
def item(owner, payload, kind, title):
    # Разобранное поле shard (тир, расшифрован ли) Мост пишет сам при приёме карточки; у сида его нет, а без него Мост не выберет шард в
    # run.breach (exhausted) — кладём его, как положил бы Мост.
    return {"owner": owner, "kind": kind, "payload": payload, "protected": False, "origin": "node:" + node,
            "in_transfer": None, "out_transfer": None, "handover": None,
            "shard": {"tier": 1, "title": title, "decrypted": True, "encrypted": False}}
def shard(i, title): return "|".join(["SHARD", i, "0", "1", b64("e2e"), b64(title), b64("meta"), b64("тело"), "0", "1"])
print(json.dumps({
    "settings": {"global": {"auditor_period_s": 3}},
    "node": {node: {"title": "Серый узел", "tier": "STANDARD", "tutorial": False, "lockdown_until": 0, "eddies": int(eddies)}},
    "terminal": {term: {"node": node, "label": "стенд e2e", "token_sha256": sha(token), "silent": False}},
    "runner": {"r_" + sha(pk)[:32]: {"key": pk, "callsign": "Alice", "blocked": False, "runs": 1, "tutorial_done": True}},
    "item": {"it_nr_shard_1": item("node:" + node, shard("nr-shard-1", "Шард e2e 1"), "SHARD", "Шард e2e 1"),
             "it_nr_shard_2": item("node:" + node, shard("nr-shard-2", "Шард e2e 2"), "SHARD", "Шард e2e 2")},
}, ensure_ascii=False))
PY
# Граф как у игры, но пустой слот пополняется через 5 с, а не через 10 мин: второй забег застаёт в хранилище второй шард
python3 - "$ROOT/netrun/data/graph.json" "$NR_DIR/graph.json" <<'PY'
import sys, json
g = json.load(open(sys.argv[1]))
g["settings"]["shard_refill_sec"]["BASE"] = 5
json.dump(g, open(sys.argv[2], "w"), ensure_ascii=False)
PY
if [ ! -x "$ROOT/netrun-bridge/build/install/netrun-bridge/bin/netrun-bridge" ] || [ -n "$(find "$ROOT/netrun-bridge/src" "$ROOT/kit/src" -newer "$ROOT/netrun-bridge/build/install/netrun-bridge/lib" -type f 2>/dev/null | head -1)" ]; then
  log "сборка Моста…"; (cd "$ROOT" && timeout 600 ./gradlew -q :netrun-bridge:installDist) > "$NR_DIR/gradle.log" 2>&1 || { tail -20 "$NR_DIR/gradle.log"; die "не собрался Мост"; }
fi
# Импорт каждый раз: старый кеш .godot не знает новых class_name, и main.gd не компилируется.
log "импорт проекта Godot…"; timeout 240 godot --headless --path "$ROOT/netrun" --import > "$NR_DIR/import.log" 2>&1
# Мост ↔ эмулятор: порт приложения пробрасывается на хост под тем же номером, Мост получает `--phone 127.0.0.1:порт=ключ Alice` (как в netrun-run)
PA=$(await 30 port_of $A); [ -n "$PA" ] || { nr_save_logs; die "порт приложения Alice не найден"; }
adb_ $A emu redir add tcp:$PA:$PA >/dev/null || die "emu redir tcp:$PA не добавился (порт занят на хосте?)"
COLLECTOR_URL="http://127.0.0.1:$PORT"
NETRUN_COLLECTOR_SECRET="${E2E_GAME_SECRET:-}" timeout 1500 "$ROOT/netrun-bridge/build/install/netrun-bridge/bin/netrun-bridge" --port $NR_BRIDGE --line-port $NR_LINE \
  --db "$NR_DIR/bridge.db" --test --seed "$NR_DIR/seed.json" --phone "127.0.0.1:$PA=$PKA" --collector "$COLLECTOR_URL" > "$NR_DIR/bridge.log" 2>&1 &
BRIDGE=$!; PIDS+=($BRIDGE)
check "Мост поднялся" wait_until 60 port_open $NR_BRIDGE
WORLD_PUB=$(node "$ROOT/scripts/e2e/netrun-bridge.mjs" $NR_BRIDGE kt hello | python3 -c "import sys,json;print(json.load(sys.stdin)['world_pub'])")
[ -n "$WORLD_PUB" ] || { nr_save_logs; die "Мост не отдал ключ мира"; }

# ── 3. Сервер мира на настоящем Мосте; хранилища закрыты (по умолчанию «auto»: у узла графа с Мостом шард берётся только взломом) ──
timeout 1500 godot --headless --path "$ROOT/netrun" -- --bridge="ws://127.0.0.1:$NR_BRIDGE" --bridge-key=kw --port=$NR_ENET --grace=20 --graph="$NR_DIR/graph.json" > "$NR_DIR/world.log" 2>&1 &
PIDS+=($!)
check "сервер мира получил снимок Моста" wait_until 120 grep -q "снимок Моста" "$NR_DIR/world.log"

RACK="MB10:RACK:v1:$TERM_ID:$(printf %s "10.0.2.2:$NR_LINE" | base64 | tr -d '\n'):$WORLD_PUB:$(printf %s "стенд e2e" | base64 | tr -d '\n')"
enter() { # enter <сколько входов уже было>: Alice сдаёт трёх демонов, защищённый — JITTER; ждём подписанный MB10ENTERED
  dbg $A DEBUG_SET --es netrun "$RACK|$D_GHOST,$D_EXTRACT,$D_JITTER|$D_JITTER"
  eq_wait 30 "вход №$1: телефон начал вход (netrun.enter_start)" "$1" entered_started
  eq_wait 90 "вход №$1: Мост ответил телефону ok=true (MB10ENTERED)" "$1" entered_ok
  eq_wait 20 "вход №$1: сданные демоны ушли с телефона" 0 phone_has daemons "$D_EXTRACT"
}
bot_args() { echo --host=127.0.0.1 --port=$NR_ENET --token="$TERM_ID:$TOKEN" --exit-after=240; }

# ── 4. Забег 1: взлом, шард, отправка Bob, чистый выход ──
adb_ $A logcat -c
enter 1
S1=$(await 20 open_session); [ -n "$S1" ] || { nr_save_logs; die "у Моста нет сессии Alice"; }
eq "сессия 1 ждёт курка (pending)" "pending/None" "$(session_view $S1)"
eq "карточки приняты Мостом: три демона в деке сессии 1" "3" "$(nrp '{"op":"list","type":"item"}' "len([i for i in d['docs'] if i['data'].get('owner')=='deck:$S1'])")"
check "терминал подтвердил сессию (session.confirm)" bash -c "node '$ROOT/scripts/e2e/netrun-bridge.mjs' $NR_BRIDGE kt '{\"op\":\"session.confirm\",\"session\":\"$S1\",\"terminal\":\"$TERM_ID\"}' | grep -q '\"ok\":true'"
GH1=$(deck_item $S1 GHOST); EX1=$(deck_item $S1 EXTRACT_SHARD)
[ -n "$GH1" ] && [ -n "$EX1" ] || { nr_save_logs; die "в деке сессии нет GHOST или EXTRACT_SHARD"; }
eq "шард 1 до взлома лежит в узле" "node:$NODE_ID" "$(item_owner it_nr_shard_1)"
timeout 260 godot --headless --path "$ROOT/netrun" -- --bot=ghost_run --bot-daemon="$GH1" --bot-give="$PKB" $(bot_args) > "$NR_DIR/bot1.log" 2>&1 &
BOT=$!; PIDS+=($BOT)
check "бот вышел чисто" wait_until 250 bash -c "grep -q '\[bot\] итог: clean' '$NR_DIR/bot1.log'"
check "бот взломал хранилище (взлом начат и закончен, хранилище открыто)" bot_said 'шаг breach' bot1
check "бот взял шард" bot_said 'шард взят' bot1
check "сервер мира принял отправку: шард ушёл контакту телефона" bot_said 'отправка: ok' bot1
check "в журнале сервера мира отправка шарда на телефон" grep -q '\[give\].*телефон' "$NR_DIR/world.log"
eq_wait 90 "Мост закрыл сессию 1 чисто" "closed/clean" session_view "$S1"

# run.breach записан Мостом в сессию (контракт 6.6)
eq "run.breach: попытка №1" 1 "$(doc_field session $S1 "data['breach']['n']")"
eq "run.breach: узел" "$NODE_ID" "$(doc_field session $S1 "data['breach']['node']")"
eq "run.breach: исход не FAIL (хранилище открыто)" True "$(doc_field session $S1 "data['breach']['outcome'] in ('SUCCESS','PARTIAL')")"
eq "run.breach: совпал EXTRACT_SHARD" True "$(doc_field session $S1 "'EXTRACT_SHARD' in data['breach']['effects']")"
eq "run.breach: открыто одно хранилище" 1 "$(doc_field session $S1 "data['breach']['opened_n']")"
eq "run.breach: хранилище не исчерпано" False "$(doc_field session $S1 "data['breach']['exhausted']")"
BREACH_EDDIES=$(doc_field session $S1 "data['breach']['eddies']")
eq "run.breach: эдди из запаса узла больше нуля" True "$([ "${BREACH_EDDIES:-0}" -gt 0 ] 2>/dev/null && echo True || echo False)"
eq "эдди забега уплачены при чистом выходе (eddies_paid = эдди взлома)" "$BREACH_EDDIES" "$(doc_field session $S1 "data['eddies_paid']")"
eq "запас эдди узла уменьшился ровно на эдди взлома" "$((NODE_EDDIES - BREACH_EDDIES))" "$(doc_field node $NODE_ID "data['eddies']")"
# Остывание узла — на нетраннере (runner.breach_cooldown), не короче времени открытия хранилища
eq "остывание: узел остывает для Alice (runner.breach_cooldown)" True "$(nrp '{"op":"list","type":"runner"}' "[r for r in d['docs'] if r['data'].get('key')=='$PKA'][0]['data'].get('breach_cooldown',{}).get('$NODE_ID',0) > $(date +%s)000")"
eq "остывание: больше 5 минут" True "$(nrp '{"op":"list","type":"runner"}' "[r for r in d['docs'] if r['data'].get('key')=='$PKA'][0]['data'].get('breach_cooldown',{}).get('$NODE_ID',0) > $(date +%s)000 + 300000")"

# Шард ушёл из деки Alice: outbox Bob (или уже его телефон), на телефоне Alice его нет
eq "шард 1 ушёл из узла и из деки Alice к Bob (outbox/телефон)" True "$(nrp '{"op":"get","type":"item","id":"it_nr_shard_1"}' "d['doc']['data']['owner'] in ('outbox:$PKB','phone:$PKB')")"
eq "шард 1 не вернулся на телефон Alice" 0 "$(phone_has shards nr-shard-1)"
eq "шард 1 не в деке сессии 1" 0 "$(nrp '{"op":"list","type":"item"}' "len([i for i in d['docs'] if i['id']=='it_nr_shard_1' and i['data'].get('owner')=='deck:$S1'])")"
eq "шард 2 остался в узле" "node:$NODE_ID" "$(item_owner it_nr_shard_2)"
# Выход чистый: демоны вернулись, шарда среди них нет
eq_wait 60 "демон GHOST вернулся на телефон" 1 phone_has daemons "$D_GHOST"
eq_wait 60 "демон EXTRACT_SHARD вернулся на телефон" 1 phone_has daemons "$D_EXTRACT"
eq_wait 60 "демон JITTER вернулся на телефон" 1 phone_has daemons "$D_JITTER"
check "бот и сервер мира без ошибок движка" bash -c "! grep -q 'SCRIPT ERROR' '$NR_DIR/world.log' '$NR_DIR/bot1.log'"

# ── 5. Записи мира у коллектора ──
eq_wait 90 "коллектор принял NET_ENTER сессии 1" 1 col_count NET_ENTER "$S1"
eq_wait 30 "коллектор принял NET_EXIT сессии 1 (чистый выход)" 1 col_count NET_EXIT "$S1"
eq "NET_EXIT 1: исход clean" clean "$(col_field NET_EXIT "$S1" outcome)"
eq_wait 30 "коллектор принял две смены владельца шарда 1 (взят из узла, отдан Bob)" 2 col_count NET_ITEM_OWNER it_nr_shard_1
eq "NET_ITEM_OWNER: шард взят из узла (take_from_node)" "node:$NODE_ID" "$(item_rec it_nr_shard_1 take_from_node from)"
eq "NET_ITEM_OWNER: шард отдан в outbox Bob (give_item)" "outbox:$PKB" "$(item_rec it_nr_shard_1 give_item to)"
eq "NET_ITEM_OWNER give_item: отправитель Alice" "$PKA" "$(item_rec it_nr_shard_1 give_item runner)"
eq "NET_ITEM_OWNER give_item: из узла" "$NODE_ID" "$(item_rec it_nr_shard_1 give_item node)"

# ── 6. Забег 2: хранилище пополнено вторым шардом, но узел остывает — взлом отказывает ──
eq_wait 60 "Alice: ждём возврата всех трёх демонов перед вторым входом (EXTRACT_SHARD)" 1 phone_has daemons "$D_EXTRACT"
enter 2
S2=$(await 20 open_session); [ -n "$S2" ] || { nr_save_logs; die "у Моста нет второй сессии Alice"; }
[ "$S2" != "$S1" ] || die "вторая сессия совпала с первой"
nrj "{\"op\":\"session.confirm\",\"session\":\"$S2\",\"terminal\":\"$TERM_ID\"}" >/dev/null
GH2=$(deck_item $S2 GHOST); EX2=$(deck_item $S2 EXTRACT_SHARD)
[ -n "$GH2" ] && [ -n "$EX2" ] || { nr_save_logs; die "во второй деке нет GHOST или EXTRACT_SHARD"; }
# Мост — последний судья: run.breach по остывающему узлу отказывает cooldown, ничего не меняя (протокол 6.6)
BREACH2="{\"op\":\"run.breach\",\"rid\":\"breach:$S2:1\",\"session\":\"$S2\",\"node\":\"$NODE_ID\",\"n\":1,\"tier\":\"BASE\",\"selected\":[\"$EX2\"],\"matched\":[\"$EX2\"],\"active\":[],\"vaults\":[\"it_nr_shard_2\"],\"open_s\":60}"
eq "Мост: run.breach по остывающему узлу — отказ cooldown" "cooldown" "$(nrp "$BREACH2" 'd["err"]["code"] if not d["ok"] else "принят"')"
eq "Мост: отказанный run.breach не открыл хранилище и не взял эдди" "None" "$(doc_field session $S2 "data.get('breach')")"
eq "Мост: запас эдди узла прежний после отказа" "$((NODE_EDDIES - BREACH_EDDIES))" "$(doc_field node $NODE_ID "data['eddies']")"
timeout 260 godot --headless --path "$ROOT/netrun" -- --bot=ghost_run --bot-daemon="$GH2" --bot-force-breach $(bot_args) > "$NR_DIR/bot2.log" 2>&1 &
BOT2=$!; PIDS+=($BOT2)
check "бот второго забега вышел чисто" wait_until 250 bash -c "grep -q '\[bot\] итог: clean' '$NR_DIR/bot2.log'"
check "сервер мира отказал во взломе: узел остывает (cooldown)" bot_said 'взлом отклонён: cooldown' bot2
eq_wait 90 "Мост закрыл сессию 2 чисто" "closed/clean" session_view "$S2"
eq "второй забег: попытки взлома в Мосте нет" "None" "$(doc_field session $S2 "data.get('breach')")"
eq "второй забег: шард 2 остался в узле" "node:$NODE_ID" "$(item_owner it_nr_shard_2)"
eq "второй забег: эдди узла не тронуты" "$((NODE_EDDIES - BREACH_EDDIES))" "$(doc_field node $NODE_ID "data['eddies']")"
eq "второй забег: шарда 2 на телефоне Alice нет" 0 "$(phone_has shards nr-shard-2)"
eq_wait 60 "второй забег: демон EXTRACT_SHARD вернулся на телефон" 1 phone_has daemons "$D_EXTRACT"
eq "остывание прежнее: взлом №2 не продлил и не сбросил его" True "$(nrp '{"op":"list","type":"runner"}' "[r for r in d['docs'] if r['data'].get('key')=='$PKA'][0]['data'].get('breach_cooldown',{}).get('$NODE_ID',0) > $(date +%s)000")"
check "боты и сервер мира без ошибок движка" bash -c "! grep -q 'SCRIPT ERROR' '$NR_DIR/world.log' '$NR_DIR/bot1.log' '$NR_DIR/bot2.log'"
eq_wait 60 "коллектор принял NET_EXIT сессии 2 (чистый выход)" 1 col_count NET_EXIT "$S2"
eq "коллектор: шард 1 по-прежнему с двумя сменами владельца (повторного взлома записи не добавили)" 2 "$(col_count NET_ITEM_OWNER it_nr_shard_1)"
eq "в журнале Моста нет отказов и ошибок отправки (sync.rejected, sync.http_error, world.derive_failed)" 0 "$(grep -cE 'sync\.rejected|sync\.http_error|sync\.bad_|world\.derive_failed' "$NR_DIR/bridge.log")"

[ $FAILED -eq 0 ] || nr_save_logs
finish
