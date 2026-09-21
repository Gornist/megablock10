#!/bin/bash
# Каркас сценариев-провокаторов для детекторов аномалий коллектора (scenarios-anomaly/*.sh).
# Отдельный экземпляр сервера: порт 2518, своя пустая БД в /tmp/mb10-e2e-anom, ускоренные окна (пульс раз в 2 с, «на связи» 15 с, низкий лимит
# запросов). Основной стенд (up.sh, порт 2517) не трогаем — сценарии можно гонять без эмуляторов, поддельные устройства (fakedev.mjs) хватает.
#   source "$(dirname "$0")/../anom-lib.sh"; anom_up [KEY=VAL ...]; ...; finish
export E2E_DIR=${ANOM_DIR:-/tmp/mb10-e2e-anom}
export PORT=${ANOM_PORT:-2518}
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ANOM_BASE_ENV="PULSE_INTERVAL_MS=2000 ONLINE_WINDOW_MS=15000 CHANGES_RATE_PER_MIN=60 ATTN_TRANSFER_STUCK_MIN=0.1"
FAKE_DIR="$E2E_DIR/fake"

# anom_up [KEY=VAL ...] — свежий сервер (пустая БД, новый мастер) с ускоренными окнами и дополнительными переменными.
anom_up() {
  local SERVER="$ROOT/admin-web/server"
  if [ ! -f "$SERVER/dist/index.js" ] || [ -n "$(find "$SERVER/src" "$SERVER/package.json" -newer "$SERVER/dist/index.js" -type f 2>/dev/null | head -1)" ]; then
    log "сборка сервера…"; (cd "$SERVER" && PATH="${NODE_BIN:+$NODE_BIN:}$PATH" npm run build >/dev/null) || die "npm run build"
  fi
  server_stop
  rm -rf "$E2E_DIR"; mkdir -p "$E2E_DIR" "$FAKE_DIR"
  (cd "$ROOT/admin-web/server" && DB_PATH="$E2E_DIR/db.sqlite" BACKUP_DIR="$E2E_DIR/backups" PATH="${NODE_BIN:+$NODE_BIN:}$PATH" npm run --silent create-master -- "$(master_name)") | tail -1 > "$E2E_DIR/master.txt" || die "create-master"
  export E2E_SERVER_ENV="$ANOM_BASE_ENV $*"
  server_start || die "сервер сценария не поднялся, см. $E2E_DIR/server.log"
  trap server_stop EXIT
}

NODE=${NODE_BIN:+$NODE_BIN/}node
# fake <команда> <имя> [опции] — поддельное устройство; результат (одна строка JSON) печатается.
fake() { "$NODE" "$ROOT/scripts/e2e/fakedev.mjs" --api "$API" --dir "$FAKE_DIR" "$@"; }
# fake_swarm <кол-во> <префикс> [опции register] — N новичков.
fake_swarm() { local n=$1 pre=$2; shift 2; local i; for i in $(seq 1 $n); do fake register "$pre$i" "$@" >/dev/null; done; }

# provision_new <позывной> <фракция> <баланс> <RAM> — выдать код персонажа (как форма в «Мастерской»); печатает номер выдачи.
provision_new() { api POST /api/provisions "{\"callsign\":\"$1\",\"faction\":\"$2\",\"balance\":$3,\"ram\":$4}" | jq_ 'd["item"]["id"]'; }
# reissue <ключ игрока> — «Выдать заново» с карточки игрока (параметры из снимка); печатает новый номер выдачи.
reissue() { api POST "/api/players/$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1")/reissue" '{}' | jq_ 'd["item"]["id"]'; }
# player_field <позывной> <поле> — поле игрока из /api/players (пусто, если игрока нет).
player_field() { api GET /api/players | jq_ "next((str(p.get('$2')) for p in d if p['callsign']=='$1'), '')"; }
players_named() { api GET /api/players | jq_ "sum(1 for p in d if p['callsign']=='$1')"; }

# kinds — виды тревог сейчас (по одному в строке).
kinds() { api GET /api/attention | jq_ '"\n".join(i["kind"] for i in d["items"])'; }
# item_count <kind> — сколько тревог такого вида.
item_count() { api GET /api/attention | jq_ "sum(1 for i in d['items'] if i['kind']=='$1')"; }
# item_field <kind> <поле> — поле первой тревоги вида.
item_field() { api GET /api/attention | jq_ "next((i['$2'] for i in d['items'] if i['kind']=='$1'), '')"; }
has_kind() { [ "$(item_count "$1")" -gt 0 ]; }
# expect_kind <kind> [секунд] — тревога должна появиться (по умолчанию за 20 с).
expect_kind() { check "тревога $1 появилась" wait_until "${2:-20}" bash -c "source '$ROOT/scripts/e2e/anom-lib.sh'; has_kind $1"; }
# expect_no_kind <kind> [пояснение] — тревоги сейчас нет (ложных срабатываний не должно быть).
expect_no_kind() { eq "${2:-без провокации тревоги $1 нет}" 0 "$(item_count "$1")"; }

ANOM_T0=$(date +%s)000
# anom_finish — сохранить вывод /api/anomalies/replay за время сценария (артефакт для подбора порогов ANOM_*) и подвести итог.
anom_finish() {
  local out="${ANOM_ARTIFACTS:-/tmp/mb10-e2e-anom-artifacts}"; mkdir -p "$out"
  api GET "/api/anomalies/replay?from=$ANOM_T0&to=$(date +%s)000&stepMin=1" > "$out/replay-$(basename "$0" .sh).json" 2>/dev/null || true
  finish
}
