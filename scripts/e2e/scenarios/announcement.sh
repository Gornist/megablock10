#!/bin/bash
# Объявление мастера: доходит до устройств, показывается окном «Сообщение от мастера», после «Принято» дашборд видит доставку.
# DEVICES — какие эмуляторы проверять (по умолчанию оба).
source "$(dirname "$0")/../lib.sh"
echo "== announcement"
DEVICES=${DEVICES:-"$A $B"}
N=$(echo $DEVICES | wc -w | tr -d ' ')
TEXT="e2e: сбор у входа в 22:00"
api POST /api/announcements "{\"text\":\"$TEXT\",\"all\":true}" >/dev/null || die "рассылка"
for s in $DEVICES; do
  check "$s: объявление сохранено на устройстве" wait_until 90 bash -c "source '$ROOT/scripts/e2e/lib.sh'; adb_ $s exec-out run-as $PKG cat shared_prefs/announcements.xml | grep -q 'e2e: сбор'"
  start_app $s; sleep 3   # дать экрану устояться: сразу после up.sh диалог и дамп UI иногда отстают
  check "$s: окно «Сообщение от мастера» на экране" wait_until 60 screen_has $s "Сообщение от мастера"
  tap_text $s "Принято" >/dev/null; sleep 1
  check "$s: после «Принято» окна нет" wait_until 10 bash -c "source '$ROOT/scripts/e2e/lib.sh'; ! screen_has $s 'Сообщение от мастера'"
done
check "дашборд: доставлено $N из $N" wait_until 60 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(api GET /api/announcements | jq_ 'str(d[0][\"delivered\"])+\"/\"+str(d[0][\"recipients\"])')\" = \"$N/$N\" ]"
finish
