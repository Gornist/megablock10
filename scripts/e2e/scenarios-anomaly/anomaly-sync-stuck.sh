#!/bin/bash
# Записи не доходят до сервера: телефон на связи (heartbeat идёт), а самая старая неотправленная запись в очереди лежит дольше порога →
# sync_stuck. Провоцируется без реальной очереди: поддельное устройство присылает presence.pendingCount/oldestPendingAgeMs напрямую в
# heartbeat, как настоящее приложение (ChangeRecordStore.presenceJson) — см. fakedev.mjs beat --pending/--oldest-ms.
source "$(dirname "$0")/../anom-lib.sh"
echo "== anomaly-sync-stuck"
anom_up ATTN_SYNC_STUCK_MIN=0.05   # 3 с
fake register SS --balance 100 >/dev/null

# Очередь есть, но самая старая запись моложе порога — обычная очередь, не тревога.
fake beat SS --pending 12 --oldest-ms 1000 >/dev/null
expect_no_kind sync_stuck "3 с ещё не прошли — тревоги нет"

# Самая старая запись старше порога — тревога, с числом записей и возрастом в минутах в описании.
fake beat SS --pending 12 --oldest-ms 600000 >/dev/null
expect_kind sync_stuck
check "в описании 12 записей и 10 минут" bash -c "source '$ROOT/scripts/e2e/anom-lib.sh'; item_field sync_stuck detail | grep -q '12 записей, самой старой 10 мин'"

# Очередь опустела на следующем heartbeat — тревога снимается, а не остаётся висеть с прежними числами.
fake beat SS --pending 0 --oldest-ms 0 >/dev/null
expect_no_kind sync_stuck "очередь опустела — тревоги нет"

anom_finish
