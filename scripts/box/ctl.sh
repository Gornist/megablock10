#!/usr/bin/env bash
# Брони и очереди devbox — выполняется НА devbox (из клона ~/box/repo; с Mac зовёт `scripts/box.sh lease|leases|release|check|run|queue`).
#   ctl.sh lease <ресурс> <владелец> <минут> [заметка…]  — взять или продлить бронь (1–480 мин); занято другим — отказ, код 1
#   ctl.sh release <ресурс> <владелец> [--force]         — снять бронь (чужую — только --force: хозяин машины или хозяин брони)
#   ctl.sh leases                                        — действующие брони (истёкшие убираются сами)
#   ctl.sh check <ресурс> <владелец>                     — 0: свободно или бронь своя; 1: чужая (для скриптов сессий)
#   ctl.sh run <класс> <владелец> [--wait сек] [--name имя] -- команда…  — выполнить в очереди класса; код выхода — команды, 3 — таймаут
#   ctl.sh queue [класс]                                 — кто держит и кто ждёт по классам; чужие замки (dbx.sh, gdUnit, display) тоже
#   ctl.sh pico status|wake <владелец> <мин> [заметка]|sleep <владелец> [--force]|guard — очки Pico: будить только под бронь `pico`,
#                                                        гасить сразу после (датчик заклеен — сами не гаснут); guard — для таймера
#   ctl.sh up <служба> <сессия> [--port N] [--ttl мин] -- команда… | down <служба> <сессия> [--purge] | inst — экземпляры служб на сессию
# Классы: gradle — замок ~/.dbx.lock (тот же, что у dbx.sh, стенда e2e и раннера CI: совместимо, переучивать их не нужно);
#         gpu — ~/box/locks/gpu.lock: сборка/экспорт Godot, кадры, Cycles (в т. ч. Nomad Surf), эмуляторы — по одному, GPU 4 ГБ;
#         light — без замка, только видно в очереди.
# Ресурсы — свободные имена; серийники устройств приводятся к именам pico / rcpad / xcover7. Примеры: rcpad, xcover7, pico,
# e2e-стенд, port:4174, forward:rcpad:9222, reverse:rcpad:4174. Бронь кооперативная: её соблюдают скрипты, зовущие `check`/`run`
# (D4), и люди; сила — в том, что её видно в `box.sh status`, а нарушение — в журнале ~/box/journal.jsonl.
set -u
BOX=${BOX:-$HOME/box}
mkdir -p "$BOX/leases" "$BOX/queue" "$BOX/locks"
NOW=$(date +%s)

hm() { date -d "@$1" +%H:%M; }
err() { echo "$*" >&2; }
alias_of() {
  case $1 in
    PA8110MGH4261073G) echo pico;;
    3063604) echo rcpad;;
    R5CY41JG61L) echo xcover7;;
    *) echo "$1";;
  esac
}
norm() { # ресурс: серийник → имя, затем проверка символов
  local r
  r=$(alias_of "$1")
  case $r in ''|*[!A-Za-z0-9_.:+-]*) err "ресурс '$1': допустимы латиница, цифры и _ . : + -"; return 1;; esac
  echo "$r"
}
get() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }
clean() { local s=${1//\\/\/}; s=${s//\"/\'}; echo "${s//[$'\n\r\t']/ }"; }
jlog() { # jlog <событие> <ключ> <значение>…
  local ev=$1 out="" k v; shift
  while [ $# -ge 2 ]; do k=$1; v=$(clean "$2"); out="$out,\"$k\":\"$v\""; shift 2; done
  printf '{"t":"%s","event":"%s"%s}\n' "$(date -Is)" "$ev" "$out" >>"$BOX/journal.jsonl"
}
class_lock() {
  case $1 in
    gradle) echo "$HOME/.dbx.lock";;
    gpu) echo "$BOX/locks/gpu.lock";;
    light) echo "";;
    *) return 1;;
  esac
}
pid_label() { # короткая подпись процесса: «возраст  командная строка»
  local pid=$1 age cmd
  age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
  cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | cut -c1-90)
  echo "pid $pid, $(( ${age:-0} / 60 )) мин: ${cmd:-?}"
}

cmd_lease() {
  [ $# -ge 3 ] || { err "использование: lease <ресурс> <владелец> <минут> [заметка…]"; return 2; }
  local res own min note f cur until
  res=$(norm "$1") || return 2; own=$2; min=$3; shift 3; note="$*"
  case $min in ''|*[!0-9]*) err "минуты — число"; return 2;; esac
  { [ "$min" -ge 1 ] && [ "$min" -le 480 ]; } || { err "минут от 1 до 480 (дольше — продлевайте)"; return 2; }
  f=$BOX/leases/$res.lease
  (
    flock 8
    if [ -f "$f" ]; then
      cur=$(get "$f" owner); until=$(get "$f" until)
      if [ "${until:-0}" -gt "$NOW" ] && [ "$cur" != "$own" ]; then
        echo "занято: $res — $cur до $(hm "$until")$(n=$(get "$f" note); [ -n "$n" ] && echo " ($n)")"
        exit 1
      fi
    fi
    { echo "owner=$own"; echo "since=$NOW"; echo "until=$((NOW + min * 60))"; echo "note=$(clean "$note")"; } >"$f.tmp" && mv "$f.tmp" "$f"
    echo "бронь: $res → $own до $(hm $((NOW + min * 60))) ($min мин)"
    jlog lease res "$res" owner "$own" minutes "$min" note "$note"
  ) 8>"$BOX/locks/leases.lock"
}

cmd_release() {
  [ $# -ge 2 ] || { err "использование: release <ресурс> <владелец> [--force]"; return 2; }
  local res own force=0 f cur until
  res=$(norm "$1") || return 2; own=$2; [ "${3:-}" = "--force" ] && force=1
  f=$BOX/leases/$res.lease
  (
    flock 8
    [ -f "$f" ] || { echo "брони $res и не было"; exit 0; }
    cur=$(get "$f" owner); until=$(get "$f" until)
    if [ "${until:-0}" -gt "$NOW" ] && [ "$cur" != "$own" ] && [ "$force" -eq 0 ]; then
      echo "бронь $res чужая ($cur до $(hm "$until")): снять может хозяин; --force — только по договорённости с ним или владельцем машины"
      exit 1
    fi
    rm -f "$f"
    echo "бронь $res снята ($own)"
    jlog release res "$res" owner "$own" was "$cur" force "$force"
  ) 8>"$BOX/locks/leases.lock"
}

cmd_leases() {
  local f res own until n any=0
  for f in "$BOX"/leases/*.lease; do
    [ -f "$f" ] || continue
    res=$(basename "$f" .lease); own=$(get "$f" owner); until=$(get "$f" until); n=$(get "$f" note)
    if [ "${until:-0}" -le "$NOW" ]; then rm -f "$f"; jlog lease-expired res "$res" owner "$own"; continue; fi
    any=1
    echo "$res: $own до $(hm "$until"), осталось $(( (until - NOW + 59) / 60 )) мин${n:+ ($n)}"
  done
  [ "$any" -eq 1 ] || echo "броней нет"
}

cmd_check() {
  [ $# -ge 2 ] || { err "использование: check <ресурс> <владелец>"; return 2; }
  local res f cur until
  res=$(norm "$1") || return 2
  f=$BOX/leases/$res.lease
  [ -f "$f" ] || return 0
  cur=$(get "$f" owner); until=$(get "$f" until)
  [ "${until:-0}" -le "$NOW" ] && return 0
  [ "$cur" = "$2" ] && return 0
  echo "занято: $res — $cur до $(hm "$until")$(n=$(get "$f" note); [ -n "$n" ] && echo " ($n)") — договоритесь с ним или подождите"
  return 1
}

# Записи очереди box (`run`): $BOX/queue/<класс>/<id>.q; мёртвые (нет процесса) убираются при чтении.
q_live() { # q_live <класс> — пути живых записей по порядку постановки
  local q pid
  for q in "$BOX/queue/$1"/*.q; do
    [ -f "$q" ] || continue
    pid=$(get "$q" pid)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then echo "$q"; else rm -f "$q"; fi
  done | sort
}
lock_rows() { # lock_rows <файл> — «pid ждёт|держит» по замку (lslocks: звёздочка у режима — ожидающий)
  lslocks -n -o PID,MODE,PATH 2>/dev/null | awk -v p="$1" '$3==p{print $1, ($2 ~ /\*/ ? "ждёт" : "держит")}'
}

show_class() {
  local c=$1 lf holders waiters q n=0 line
  lf=$(class_lock "$c") || { err "класс '$c': gradle | gpu | light"; return 2; }
  if [ -n "$lf" ]; then
    holders=$(lock_rows "$lf" | awk '$2=="держит"{print $1}' | sort -u)
    waiters=$(lock_rows "$lf" | awk '$2=="ждёт"{print $1}' | sort -u | wc -l | tr -d ' ')
    if [ -z "$holders" ]; then line="свободно"; else
      line="занято: $(for p in $holders; do pid_label "$p"; done | head -2 | paste -sd';' -)"
    fi
    echo "$c ($lf): $line$([ "${waiters:-0}" -gt 0 ] && echo "; ждут: $waiters")"
  else
    echo "$c (без замка):"
  fi
  while read -r q; do
    [ -n "$q" ] || continue
    n=$((n + 1))
    echo "    $n. $(get "$q" owner): $(get "$q" name) — $(get "$q" state) с $(hm "$(get "$q" since)")"
  done < <(q_live "$c")
}
cmd_queue() {
  if [ $# -ge 1 ]; then show_class "$1"; return; fi
  show_class gradle; show_class gpu; show_class light
  # замки сессий, о которых box не знает (Godot dev.sh): показываем, чтобы «почему не запускается» читалось
  local f rows
  for f in /tmp/gdunit.lock /tmp/display.lock; do
    rows=$(lock_rows "$f" | awk '$2=="держит"{print $1}' | sort -u | head -1)
    if [ -n "$rows" ]; then echo "$f: занято: $(pid_label "$rows")"; fi
  done
}

cmd_run() {
  [ $# -ge 3 ] || { err "использование: run <класс> <владелец> [--wait сек] [--name имя] -- команда…"; return 2; }
  local class=$1 own=$2 wait=2700 name="" lf id rc t0
  shift 2
  while [ $# -gt 0 ]; do
    case $1 in
      --wait) wait=${2:-2700}; shift 2;;
      --name) name=${2:-}; shift 2;;
      --) shift; break;;
      *) err "ожидался -- перед командой (получено '$1')"; return 2;;
    esac
  done
  [ $# -gt 0 ] || { err "нет команды после --"; return 2; }
  lf=$(class_lock "$class") || { err "класс '$class': gradle | gpu | light"; return 2; }
  [ -n "$name" ] || name=$(basename "$1")
  mkdir -p "$BOX/queue/$class"
  id=$(date +%s%N)-$$
  RUNQ=$BOX/queue/$class/$id.q
  { echo "owner=$own"; echo "name=$(clean "$name")"; echo "pid=$$"; echo "state=ждёт"; echo "since=$NOW"; } >"$RUNQ"
  trap 'rm -f "$RUNQ"' EXIT
  trap 'exit 130' INT TERM
  if [ -n "$lf" ]; then
    exec 9>"$lf"
    if ! flock -n 9; then
      echo "очередь $class: занято, жду (до ${wait} с) — scripts/box.sh queue $class"
      jlog queue-wait class "$class" owner "$own" name "$name"
      if ! flock -w "$wait" 9; then
        echo "очередь $class: таймаут ожидания ${wait} с"; jlog queue-timeout class "$class" owner "$own" name "$name"
        return 3
      fi
    fi
  fi
  t0=$(date +%s)
  sed -i 's/^state=.*/state=идёт/' "$RUNQ"
  jlog run-start class "$class" owner "$own" name "$name"
  "$@" 9>&-
  rc=$?
  jlog run-done class "$class" owner "$own" name "$name" rc "$rc" sec "$(( $(date +%s) - t0 ))"
  return "$rc"
}

# --- очки Pico: сон и пробуждение -------------------------------------------------------------------------------------------
# Датчик приближения заклеен (решение владельца 13.10, через Pipeline): сами очки не гаснут, а матрицы выгорают. Поэтому будим
# только под бронь `pico` и гасим сразу после. KEYCODE_SLEEP на Pico не работает, работает KEYCODE_POWER — но это ПЕРЕКЛЮЧАТЕЛЬ:
# на спящих очках он будит. Поэтому состояние читаем всегда перед нажатием и проверяем после; повтор — один раз и только
# после нового чтения состояния.
PICO=${PICO:-PA8110MGH4261073G}
ADB=${ADB:-$HOME/android-sdk/platform-tools/adb}
# Защита от тестов, трогающих живые очки (13.10 ~17:27 тест «отказ по чужой брони» запустил серию на реальных очках):
# тест ставит BOX_TEST=1 — тогда рабочий ~/box (брони, журнал) и настоящий adb запрещены, нужны подложные BOX и ADB.
if [ "${BOX_TEST:-}" = 1 ]; then
  case ${BOX%/} in "$HOME/box") err "BOX_TEST=1: BOX — рабочий ~/box; тест не должен писать в живые брони и журнал (задайте BOX=/tmp/…)"; exit 3;; esac
  case $ADB in "$HOME/android-sdk/platform-tools/adb"|adb) err "BOX_TEST=1: ADB — настоящий; подложите свой (ADB=/tmp/…/adb)"; exit 3;; esac
fi
PICO_GRACE=${PICO_GRACE:-180}  # секунд без брони, после которых guard гасит очки
pico_state() { # Awake | Asleep | Dozing | ? ; второй токен — Display Power: ON|OFF|?
  local raw w d
  raw=$(timeout 10 "$ADB" -s "$PICO" shell 'dumpsys power | grep -E "mWakefulness=|Display Power: state"' </dev/null 2>/dev/null | tr -d '\r')
  w=$(sed -n 's/.*mWakefulness=\([A-Za-z]*\).*/\1/p' <<<"$raw" | head -1)
  d=$(sed -n 's/.*Display Power: state=\([A-Z]*\).*/\1/p' <<<"$raw" | head -1)
  echo "${w:-?} ${d:-?}"
}
pico_power() { timeout 10 "$ADB" -s "$PICO" shell input keyevent KEYCODE_POWER </dev/null >/dev/null 2>&1; }
pico_wait() { # pico_wait <Awake|Asleep> <секунд> → 0, если очки пришли в состояние
  local want=$1 i st
  for ((i = 0; i < $2; i++)); do
    st=$(pico_state)
    case $want in
      Awake) [ "${st%% *}" = Awake ] && return 0;;
      Asleep) [ "${st%% *}" = Asleep ] && [ "${st##* }" = OFF ] && return 0;;
    esac
    sleep 1
  done
  return 1
}
pico_lease_owner() { # владелец действующей брони pico или пусто
  local f=$BOX/leases/pico.lease until
  [ -f "$f" ] || return 0
  until=$(get "$f" until)
  [ "${until:-0}" -gt "$NOW" ] && get "$f" owner
}
pico_sleep_now() { # → 0 очки Asleep/OFF (нажимаем POWER только если они Awake)
  local st
  pico_unpark_card  # карточка границы (если её парковали под игру) — обратно на дисплей 0, пока очки не погасли
  st=$(pico_state)
  case ${st%% *} in
    Asleep) return 0;;
    Awake|Dozing) ;;
    *) err "очки: состояние неизвестно ($st) — не нажимаю POWER вслепую"; return 1;;
  esac
  pico_power
  pico_wait Asleep 8 && return 0
  st=$(pico_state)  # повтор один раз и только по свежему чтению: POWER на спящих очках будит
  if [ "${st%% *}" = Awake ] || [ "${st%% *}" = Dozing ]; then pico_power; pico_wait Asleep 8 && return 0; fi
  return 1
}

PICO_UI_PY=$(dirname "$(readlink -f "$0")")/pico_ui.py
# Состояние очков по свойствам системы, а не только по дампу uiautomator: оверлеи Unity (граница, «Слишком темно») он не видит.
# Замер 13.10 18:40 на живых очках (Awake, окно «Слишком темно» на экране; см. docs/devbox.md, «Д5»):
#   settings global pvr.app.data.light_warning_state=1          ← окно «Слишком темно» показано (подтверждено кадром)
#   mResumedActivity=com.pvr.seethrough.setting/.MainActivity   ← то же окно; ТОТ ЖЕ пакет, что у окна границы
#   settings global pvr.app.data.top_app_on_default_display      = com.pvr.seethrough.setting/.MainActivity
#   sys.pxr.boundary.ready=0, sys.pxr.trackingservice.algstate=1 (спящие: 2), …alg_confidence=0
# `dumpsys window` перечисляет окна ВСЕХ дисплеев и задач, первое совпадение — часто устаревшее (HandDialogActivity): на нём
# построенный pico_fg давал ложное ГОТОВО. Верхнюю активность берём из `dumpsys activity activities` (mResumedActivity).
P_BOUND="" P_ALG="" P_CONF="" P_LIGHT="" P_TOP="" P_RES=""
pico_props() { # заполняет P_* (пусто — не удалось прочитать)
  local raw
  raw=$(timeout 20 "$ADB" -s "$PICO" shell 'for k in sys.pxr.boundary.ready sys.pxr.trackingservice.algstate sys.pxr.trackingservice.alg_confidence; do echo "$k=$(getprop $k)"; done; echo "light_warning=$(settings get global pvr.app.data.light_warning_state)"; echo "top_app=$(settings get global pvr.app.data.top_app_on_default_display)"; dumpsys activity activities | grep -m1 mResumedActivity' </dev/null 2>/dev/null | tr -d '\r')
  P_BOUND=$(sed -n 's/^sys\.pxr\.boundary\.ready=//p' <<<"$raw" | head -1)
  P_ALG=$(sed -n 's/^sys\.pxr\.trackingservice\.algstate=//p' <<<"$raw" | head -1)
  P_CONF=$(sed -n 's/^sys\.pxr\.trackingservice\.alg_confidence=//p' <<<"$raw" | head -1)
  P_LIGHT=$(sed -n 's/^light_warning=//p' <<<"$raw" | head -1)
  P_TOP=$(sed -n 's/^top_app=//p' <<<"$raw" | head -1)
  P_RES=$(grep mResumedActivity <<<"$raw" | grep -o -E 'u[0-9]+ [A-Za-z0-9_.]+/[A-Za-z0-9_.$]+' | head -1 | cut -d' ' -f2)
  # запасной источник: настройка «верхнее приложение» (на замере совпала с mResumedActivity)
  case ${P_TOP:-} in */*) [ -n "$P_RES" ] || P_RES=$P_TOP;; esac
}
pico_fg() { pico_props; echo "$P_RES"; } # «пакет/активити» верхнего окна (совместимость со старым именем)
pico_uidump() { # XML экрана на stdout; пусто — uiautomator экран не отдал (оверлеи он не видит)
  timeout 20 "$ADB" -s "$PICO" shell uiautomator dump /sdcard/box-ui.xml </dev/null >/dev/null 2>&1
  timeout 15 "$ADB" -s "$PICO" exec-out cat /sdcard/box-ui.xml </dev/null 2>/dev/null
}
pico_shot() { # pico_shot [файл] → путь к PNG (screencap) или пусто; без аргумента — ~/box/shots, последние 20
  local f=${1:-} std=0
  if [ -z "$f" ]; then std=1; mkdir -p "$BOX/shots"; f=$BOX/shots/pico-$(date +%m%d-%H%M%S).png; fi
  timeout 20 "$ADB" -s "$PICO" exec-out screencap -p </dev/null >"$f" 2>/dev/null
  if [ -s "$f" ]; then
    [ "$std" = 1 ] && { ls -1t "$BOX"/shots/pico-*.png 2>/dev/null | tail -n +21 | xargs -r rm -f; }
    echo "$f"
  else rm -f "$f"; fi
}
PICO_BOUNDARY_PKG=${PICO_BOUNDARY_PKG:-com.pvr.seethrough.setting}  # окно границы И «Слишком темно» — Unity в одном пакете, нод в дампе нет
# Системные пакеты на переднем плане, с которыми запускать нельзя; свои — в $BOX/pico-bad-pkgs (по строке).
PICO_BAD_PKGS="com.pvr.seethrough.setting com.picovr.systemext com.picovr.settings com.pvr.appmanager $(cat "$BOX/pico-bad-pkgs" 2>/dev/null | tr '\n' ' ')"
# Допустимое на переднем плане: наша игра и лаунчер (ПО ПУСТОМУ списку не угадать — расширяется файлом $BOX/pico-ok-pkgs
# по строке или PICO_OK_PKGS; неизвестный пакет = НЕ ГОТОВО с названием в вердикте, а не молчаливое «можно»).
PICO_OK_PKGS="${PICO_OK_PKGS:-com.megablok10.netrun com.pvr.home com.picovrtob.vrlauncher com.pvr.vrshell} $(cat "$BOX/pico-ok-pkgs" 2>/dev/null | tr '\n' ' ')"
# sys.pxr.boundary.ready=1 как условие «готово» ОТМЕНЕНО: замер 13.10 21:03–21:05 (3 прогона, игра resumed на дисплее 0, трекинг 1/1)
# — значение остаётся 0, пока карточка границы не подтверждена человеком, а игре оно не мешает. Включить: PICO_REQUIRE_BOUNDARY=1.
PICO_REQUIRE_BOUNDARY=${PICO_REQUIRE_BOUNDARY:-0}
PICO_LEASE_NOTE="бронь оставлена"  # внутри pico run меняется на «бронь снимет run»
DIAG_WHY="" DIAG_KIND=""
pico_diagnose() { # 0 — состояние здоровое; иначе DIAG_WHY (причина текстом) и DIAG_KIND: physical | window | unknown | state
  local pkg
  pico_props
  DIAG_WHY=""; DIAG_KIND=""
  # light_warning_state — ЛИПКИЙ флаг: замер Pipeline 18:48 (лампа на очки) — при свете он остаётся 1, поэтому признаком «темно»
  # не служит (только справочно в `pico fg`). Живой признак — трекинг: тёмная комната algstate=2/conf=-1 или 1/0; со светом через ~6 с
  # после пробуждения algstate=1, alg_confidence=1 (в первые ~3 с: algstate=0, conf=-1 — трекинг ещё стартует).
  if [ -z "$P_RES" ]; then DIAG_WHY="не удалось прочитать верхнее окно очков (mResumedActivity пуст)"; DIAG_KIND=state; return 1; fi
  pkg=${P_RES%%/*}
  if ! pico_track_ok; then
    DIAG_WHY="трекинг не работает: alg_confidence=${P_CONF:-?}, algstate=${P_ALG:-?} — темно (нужен свет у очков) или мало текстур; на экране $P_RES"
    DIAG_KIND=physical; return 1
  fi
  # карточка границы допустима, пока `pico start` не снял её парковкой (pico_ready выставляет PICO_CARD_OK; трекинг проверен выше)
  if [ "$PICO_CARD_OK" = 1 ] && [ "$pkg" = "$PICO_BOUNDARY_PKG" ]; then return 0; fi
  case " $PICO_BAD_PKGS " in *" $pkg "*) DIAG_WHY="системное окно на переднем плане: $P_RES"; DIAG_KIND=window; return 1;; esac
  case " $PICO_OK_PKGS " in *" $pkg "*) ;; *) DIAG_WHY="неизвестное окно на переднем плане: $P_RES (не игра и не лаунчер; известные: ${PICO_OK_PKGS})"; DIAG_KIND=unknown; return 1;; esac
  if [ "$PICO_REQUIRE_BOUNDARY" = 1 ] && [ "$P_BOUND" != 1 ]; then
    DIAG_WHY="граница не готова: sys.pxr.boundary.ready=${P_BOUND:-пусто} (окно $P_RES)"; DIAG_KIND=state; return 1
  fi
  return 0
}
pico_track_ok() { # 0 — трекинг работает (alg_confidence >= 1); нет числа — считаем неработающим: «не знаем» ≠ «можно»
  case ${P_CONF:-} in ''|*[!0-9-]*) return 1;; esac
  [ "$P_CONF" -ge 1 ]
}
pico_todo() { # что сделать человеку — по виду причины (текст уходит владельцу пушем, поэтому коротко и по делу)
  case $1 in
    physical) echo "Включить свет у очков (лампа) — трекинг не работает; затем перезапустить прогон";;
    window) echo "Открыть PNG: системное окно Pico на экране. Снять его вручную в очках; если окно новое — сказать Devbox (добавлю в белый список)";;
    unknown) echo "Открыть PNG: что за окно или пакет. Закрыть вручную; если это нормальный экран — добавить пакет в ~/box/pico-ok-pkgs";;
    taps) echo "Разрешить нажатия белого списка (pico taps on) либо снять окно вручную в очках";;
    boundary) echo "Надеть очки и один раз нажать «Войти в VR (текущая граница)» — карточка границы не закрывается через adb; затем перезапустить прогон";;
    state) echo "Надеть очки и пройти настройку границы/трекинга вручную, затем перезапустить прогон";;
    wake) echo "Очки не просыпаются: проверить питание очков, кабель USB и adb (box.sh status)";;
    adb) echo "Лишний adb-сервер прячет очки от основного: scripts/box.sh adb-rescue (Devbox/Pipeline); если у сервера есть клиенты — договориться с хозяином";;
    asleep) echo "ПОГАСИТЬ ОЧКИ ВРУЧНУЮ (кнопка питания): риск выгорания матриц";;
    timeout) echo "Прогон не уложился во время: посмотреть журнал прогона, очки погашены, перезапустить";;
    *) echo "Посмотреть PNG и журнал ~/box/journal.jsonl";;
  esac
}
pico_attention() { # pico_attention <владелец> <причина> <png> [вид] — JSON-строка в ~/box/attention.log (читает Pipeline, шлёт владельцу пушем)
  # Одна причина — одна строка: повтор той же причины не пишется, пока не было успешного ready (его сбрасывает pico_ready).
  local own=$1 why=$2 png=${3:-} kind=${4:-other} last
  last=$(cat "$BOX/attention.last" 2>/dev/null)
  [ "$last" = "$kind|$why" ] && return 0
  printf '%s' "$kind|$why" >"$BOX/attention.last"
  printf '{"t":"%s","owner":"%s","kind":"%s","reason":"%s","todo":"%s","png":"%s"}\n' \
    "$(date -Is)" "$(clean "$own")" "$kind" "$(clean "$why")" "$(clean "$(pico_todo "$kind")")" "$(clean "$png")" >>"$BOX/attention.log"
}
pico_is_human() { # владелец брони — человек (очки могут быть на нём): автоматике НЕЛЬЗЯ ни парковать карточку, ни гасить очки
  # (инцидент 14.10 ~10:00: при брони «Владелец» сработала парковка — в очках пусто, adb пропал). Свои имена — ~/box/pico-human-owners.
  # Сравнение без зависимости от локали: в неинтерактивном ssh локаль C и ${x,,} кириллицу не понижает (тест 14.10 поймал).
  local o=${1:-} h
  [ -n "$o" ] || return 1
  for h in Владелец владелец ВЛАДЕЛЕЦ Owner owner OWNER $(cat "$BOX/pico-human-owners" 2>/dev/null); do
    [ "$o" = "$h" ] && return 0
  done
  return 1
}
pico_fail() { # pico_fail <владелец> <окно> <причина> [вид] — PNG, attention, очки гасим (если не человек), бронь оставляем; код 1
  local shot sleepnote="очки погашены"
  shot=$(pico_shot)
  if pico_is_human "$1" || pico_is_human "$(pico_lease_owner)"; then
    # человек может быть в очках: POWER не жмём (выключили бы на нём); карточку, если парковали, возвращаем
    pico_unpark_card; sleepnote="очки НЕ гашу (бронь человека)"
  else
    pico_sleep_now >/dev/null 2>&1
  fi
  jlog pico-ready-fail owner "$1" window "$2" reason "$3" png "${shot:-}"
  pico_attention "$1" "$3" "$shot" "${4:-other}"
  echo "pico ready: НЕ ГОТОВО — $3; PNG: ${shot:-нет}; ${sleepnote}, ${PICO_LEASE_NOTE}"
  return 1
}
# Карточка границы (com.pvr.seethrough.setting, Unity): ввод Android её не закрывает (опыт 13.10 20:30), HOME и force-stop — тоже
# (система сразу возвращает свой компонент). Работает ПАРКОВКА: перенос стека карточки на другой дисплей (`am display move-stack`,
# разрешено владельцем напрямую в чате сессии Devbox 13.10 для тестовых очков) — игра выходит на передний план дисплея 0
# (resumed, 15+ с). Карточку возвращаем на дисплей 0 при гашении очков (pico_unpark_card) — защитное окно на своём месте.
# Рамка/дисплеи (замер): карточка — Display 0, [0,0][4320,2160]; виртуальный дисплей 2 — 4320x4320, 560dpi.
PICO_PARK_DISPLAY=${PICO_PARK_DISPLAY:-}  # номер дисплея для парковки; пусто — найти по размеру 4320x4320
PICO_CARD_OK=0                             # 1 — карточка на экране допустима (pico_ready: её снимет `pico start`)
pico_stack_of() { # pico_stack_of <пакет> → id стека, где задача пакета
  timeout 15 "$ADB" -s "$PICO" shell am stack list </dev/null 2>/dev/null | tr -d '\r' \
    | awk -v p="$1" '/^Stack id=/{split($2,a,"="); sid=a[2]} index($0,p){print sid; exit}'
}
pico_park_display() { # id виртуального дисплея 4320x4320 (не 0) или $PICO_PARK_DISPLAY
  [ -n "$PICO_PARK_DISPLAY" ] && { echo "$PICO_PARK_DISPLAY"; return; }
  timeout 15 "$ADB" -s "$PICO" shell dumpsys window displays </dev/null 2>/dev/null | tr -d '\r' \
    | awk '/Display: mDisplayId=/{split($2,a,"="); id=a[2]} /init=4320x4320/{if (id != 0) {print id; exit}}'
}
pico_boot_id() { timeout 10 "$ADB" -s "$PICO" shell cat /proc/sys/kernel/random/boot_id </dev/null 2>/dev/null | tr -d '\r\n '; }
pico_park_card() { # pico_park_card <владелец>: карточка → на виртуальный дисплей; 0 — карточка с переднего плана ушла
  # ТОЛЬКО автопрогон (pico run выставляет PICO_PARK_OK=1 команде) и НИКОГДА при брони человека: инцидент 14.10 ~10:00 — при
  # показе владельцу в очках парковка оставила в них пустоту (игра без подтверждённого «Войти в VR», окон нет), затем пропал adb.
  local own=$1 sid disp i boot
  if [ "${PICO_PARK_OK:-0}" != 1 ] || pico_is_human "$own" || pico_is_human "$(pico_lease_owner)"; then
    DIAG_WHY="карточка границы на экране, а парковка разрешена только автопрогону (pico run) и не при брони человека («$own»): подтвердите «Войти в VR» в очках"
    DIAG_KIND=boundary; return 1
  fi
  sid=$(pico_stack_of "$PICO_BOUNDARY_PKG"); disp=$(pico_park_display); boot=$(pico_boot_id)
  if [ -z "$sid" ] || [ -z "$disp" ]; then
    DIAG_WHY="карточка границы: не нашёл стек (${sid:-?}) или дисплей для парковки (${disp:-?})"; DIAG_KIND=boundary; return 1
  fi
  jlog pico-park-card owner "$own" stack "$sid" display "$disp"
  printf '%s %s' "$sid" "${boot:-?}" >"$BOX/pico-parked.stack"  # сначала запись (чтобы любой выход вернул), потом перенос
  timeout 15 "$ADB" -s "$PICO" shell am display move-stack "$sid" "$disp" </dev/null >/dev/null 2>&1
  for i in 1 2 3 4 5 6; do
    sleep 1
    pico_props
    case ${P_RES:-?} in "$PICO_BOUNDARY_PKG"/*) ;; *) return 0;; esac
  done
  DIAG_WHY="карточка границы осталась на переднем плане после переноса стека $sid на дисплей $disp"; DIAG_KIND=boundary
  return 1
}
pico_unpark_card() { # вернуть карточку на дисплей 0 (если её парковали); безвредно без парковки
  # Файл хранит «стек boot_id»: после перезагрузки очков номера стеков другие — переносить «по номеру» чужой стек нельзя.
  local f=$BOX/pico-parked.stack sid boot now
  [ -f "$f" ] || return 0
  read -r sid boot <"$f"
  [ -n "$sid" ] || { rm -f "$f"; return 0; }
  now=$(pico_boot_id)
  if [ -z "$now" ]; then return 0; fi  # очки сейчас недоступны по adb — файл оставляем, вернём при следующем гашении/пробуждении
  if [ "$now" != "$boot" ] || [ "$(pico_stack_of "$PICO_BOUNDARY_PKG")" != "$sid" ]; then
    rm -f "$f"; jlog pico-unpark-skip stack "$sid" note "очки перезагружались или стек не карточка — не трогаю"; return 0
  fi
  rm -f "$f"
  timeout 15 "$ADB" -s "$PICO" shell am display move-stack "$sid" 0 </dev/null >/dev/null 2>&1
  jlog pico-unpark-card stack "$sid"
}
pico_ready() { # pico_ready <владелец>: бронь → разбудить → снять известные безопасные окна → проверить СОСТОЯНИЕ очков
  local own=$1 lo st v kind rid xy btn title shot why n_tap=0 i state
  PICO_CARD_OK=0
  lo=$(pico_lease_owner)
  if [ "$lo" != "$own" ]; then
    echo "pico ready: нет брони pico у $own (сейчас: ${lo:-никого}) — сначала pico wake $own <мин>"; return 1
  fi
  st=$(pico_state)
  case ${st%% *} in
    Awake) ;;
    Asleep|Dozing)
      pico_power
      pico_wait Awake 8 || { echo "pico ready: очки не проснулись за 8 с ($(pico_state)); ${PICO_LEASE_NOTE}"; pico_attention "$own" "очки не проснулись по POWER ($(pico_state))" "" wake; return 1; };;
    *) stray=$(adb_stray_text)
       if [ -n "$stray" ]; then
         # очки есть в USB, но основной adb их не видит: их держит лишний adb-сервер (инцидент 14.10) — это не «очки не отвечают»
         why="очки не видны основному adb: ${stray}держит USB-устройства. Вернуть: scripts/box.sh adb-rescue (не трогает серверы с клиентами; рвёт forward/reverse на секунды и возвращает)"
         echo "pico ready: НЕ ГОТОВО — $why; ${PICO_LEASE_NOTE}"; pico_attention "$own" "$why" "" adb; return 1
       fi
       echo "pico ready: очки не отвечают ($st); ${PICO_LEASE_NOTE}"; pico_attention "$own" "очки не отвечают на adb ($st)" "" wake; return 1;;
  esac
  # Один цикл вместо двух (прогон Godot 20:00: conf=1 появился ПОСЛЕ 4 проходов × 2 с, а итоговая проверка уже не нажимала —
  # «НЕ ГОТОВО: window seethrough.setting» при живом трекинге). До PICO_READY_PASSES проходов по ~2 с (по умолчанию 12 ≈ 25–30 с):
  # трекинг оседает ~6 с после пробуждения, плюс POWER и загрузка окон. Выход — как только состояние здоровое.
  for _ in $(seq 1 "${PICO_READY_PASSES:-12}"); do
    sleep 2  # интерфейс после пробуждения/нажатия оседает не мгновенно
    pico_props
    # карточка границы (пакет seethrough.setting, Unity, без нод): ввод её не закрывает — это НЕ «не готово», а штатный экран
    # при пробуждении; её снимает `pico start` парковкой стека на другой дисплей. В том же пакете живёт «Слишком темно»
    # (light_warning_state липкий, по нему не отличить): карточка допустима, только когда трекинг работает
    # (alg_confidence >= 1; стартует ~6 с после пробуждения — до тех пор ждём следующий проход).
    case ${P_RES:-?} in
      "$PICO_BOUNDARY_PKG"/*)
        pico_track_ok || continue
        PICO_CARD_OK=1; break;;
    esac
    v=$(pico_uidump | python3 "$PICO_UI_PY" 2>/dev/null)
    kind=${v%%$'\t'*}
    if [ "$kind" != KNOWN ]; then
      pico_diagnose && break  # здорово — выходим сразу
      continue                # не здорово (трекинг/окно ещё оседают) — ждём следующий проход
    fi
    IFS=$'\t' read -r _ rid xy btn title <<<"$v"
    if [ ! -f "$BOX/pico-ready.taps" ]; then
      why="известное окно «${title:-$rid}», кнопка «$btn» — нажатия выключены (pico taps on — решение владельца)"
      jlog pico-ready-blocked owner "$own" window "$rid" button "$btn"
      pico_fail "$own" "$rid" "$why" taps; return 1
    fi
    n_tap=$((n_tap + 1))
    # shellcheck disable=SC2086  # xy = «x y» из дампа, разбиение намеренное
    timeout 10 "$ADB" -s "$PICO" shell input tap $xy </dev/null >/dev/null 2>&1
    jlog pico-ready-tap owner "$own" window "$rid" title "$title" button "$btn" at "$xy"
  done
  # итог: один свежий диагноз (цикл выше уже ждал оседания); карточка границы при работающем трекинге допустима
  pico_diagnose
  if [ -n "$DIAG_WHY" ]; then
    jlog pico-ready-diag owner "$own" kind "$DIAG_KIND" res "${P_RES:-}" light "${P_LIGHT:-}" boundary "${P_BOUND:-}" alg "${P_ALG:-}" conf "${P_CONF:-}"
    pico_fail "$own" "${P_RES:-?}" "$DIAG_WHY" "$DIAG_KIND"; return 1
  fi
  state="окно $P_RES, граница=${P_BOUND:-?}, трекинг algstate=${P_ALG:-?}/conf=${P_CONF:-?}"
  jlog pico-state owner "$own" res "$P_RES" light "${P_LIGHT:-}" boundary "${P_BOUND:-}" alg "${P_ALG:-}" conf "${P_CONF:-}" taps "$n_tap"
  rm -f "$BOX/attention.last"  # успех: следующая такая же причина снова станет строкой в attention.log
  [ "$PICO_CARD_OK" = 1 ] && state="карточка границы на экране (снимется при pico start), $state"
  echo "pico ready: ГОТОВО — $state${n_tap:+, нажатий белого списка: $n_tap}"
}
pico_start() { # pico_start <владелец> <пакет/активити>: am start, карточку границы (если есть) — парковкой; игра ДОЛЖНА быть resumed
  # Порядок (опыты 13.10): am start → если система держит окно («kept for the user») — HOME и один повтор (разрешено владельцем);
  # игра стартует, но остаётся paused ЗА карточкой (seethrough.setting) — тогда стек карточки на другой дисплей.
  local own=$1 comp=$2 out pkg i parked=0 low stray
  pkg=${comp%%/*}
  if ! "$ADB" devices 2>/dev/null | grep -q "^${PICO}[[:space:]]*device"; then
    stray=$(adb_stray_text)
    if [ -n "$stray" ]; then
      DIAG_WHY="очки не видны основному adb: ${stray}держит USB-устройства — scripts/box.sh adb-rescue"
      pico_attention "$own" "$DIAG_WHY" "" adb; echo "pico start: НЕ ГОТОВО — $DIAG_WHY"; return 1
    fi
  fi
  out=$(timeout 30 "$ADB" -s "$PICO" shell am start -n "$comp" </dev/null 2>&1 | tr -d '\r')
  low=$(tr 'A-Z' 'a-z' <<<"$out")
  case $low in
    *"kept for the user"*)
      jlog pico-start-home owner "$own" note "am start: kept for the user — KEYCODE_HOME и повтор"
      timeout 10 "$ADB" -s "$PICO" shell input keyevent KEYCODE_HOME </dev/null >/dev/null 2>&1; sleep 2
      out=$(timeout 30 "$ADB" -s "$PICO" shell am start -n "$comp" </dev/null 2>&1 | tr -d '\r'); low=$(tr 'A-Z' 'a-z' <<<"$out");;
  esac
  case $low in
    *"kept for the user"*|*"error"*|*"does not exist"*|*"exception"*)
      pico_fail "$own" start "am start $comp: «$(head -c 160 <<<"$out" | tr '\n' ' ')» — игра не вышла на передний план" window; return 1;;
  esac
  for i in 1 2 3 4 5 6 7 8; do
    sleep 2
    pico_props
    case ${P_RES:-?} in
      "$pkg"/*) echo "pico start: $comp на переднем плане${parked:+ (карточка границы убрана на другой дисплей)}"; return 0;;
      "$PICO_BOUNDARY_PKG"/*)
        if [ "$parked" = 0 ] && pico_track_ok; then
          pico_park_card "$own" || { pico_fail "$own" start "$DIAG_WHY" boundary; return 1; }
          parked=1
        fi;;
    esac
  done
  pico_fail "$own" start "после am start $comp на переднем плане ${P_RES:-?}, а не игра" window
}
RUN_OWN="" RUN_CREATED=0 RUN_DONE=0 RUN_PORT="" RUN_PORT_CREATED=0
pico_run_cleanup() { # при ЛЮБОМ выходе: очки гаснут, брони, созданные run, снимаются; повторный вызов безвреден
  [ "$RUN_DONE" = 1 ] && return 0
  RUN_DONE=1
  trap - EXIT INT TERM HUP
  if pico_is_human "$RUN_OWN"; then
    pico_unpark_card  # бронь человека: POWER не жмём (очки могут быть на нём), карточку — на место
  elif ! pico_sleep_now >/dev/null 2>&1; then
    pico_attention "$RUN_OWN" "очки НЕ погасли после прогона ($(pico_state)) — выгорание матриц, нужен человек" "" asleep
  fi
  [ "$RUN_PORT_CREATED" = 1 ] && cmd_release "port:$RUN_PORT" "$RUN_OWN" >/dev/null 2>&1
  [ "$RUN_CREATED" = 1 ] && cmd_release pico "$RUN_OWN" >/dev/null 2>&1
  pico_light off
  jlog pico-run-end owner "$RUN_OWN" released "$RUN_CREATED"
}
# Свет у очков (решение владельца 13.10: против темноты — лампа у места, где лежат очки). Как её включать — выбирает тот, кто её
# подключил: исполняемые файлы ~/box/pico-light-on и ~/box/pico-light-off (умная розетка, uhubctl, реле). Нет файла — run ничего
# не делает со светом. Ошибка команды света не роняет прогон, но пишется в журнал.
pico_light() { # pico_light on|off
  local f=$BOX/pico-light-$1
  [ -x "$f" ] || return 0
  timeout 30 "$f" </dev/null >/dev/null 2>&1; jlog pico-light state "$1" rc "$?"
}
# pico run <владелец> <минут> [--timeout сек] [--port N] [--dir каталог] -- команда…
#   бронь pico (и port:N) → разбудить → ready (по СОСТОЯНИЮ системы, не только по дампу) → logcat -c, снимок «до» → команда →
#   снимок «после», logcat -d → погасить очки → снять созданные брони. Выход: код команды; 20 — не готово/вылезло окно, команда
#   не стартовала или результат под вопросом; 21 — бронь занята чужим; 124 — таймаут. Окружение команды: PICO_SERIAL,
#   PICO_RUN_DIR (снимки/logcat прогона), BOX_OWNER, BOX_CTL (путь к ctl.sh — для pico ready/fg/start внутри команды).
#   Вердикт — последняя строка: «pico run: ОК|НЕ ГОТОВО|ТАЙМАУТ|… — …». Команда идёт под продлением брони `<минут>`: дольше —
#   таймаут (не «гасить посреди варианта»: серию делить на несколько run или брать минут с запасом).
pico_run() {
  [ $# -ge 4 ] || { err "использование: pico run <владелец> <минут> [--timeout сек] [--port N] [--dir каталог] -- команда…"; return 2; }
  local own=$1 min=$2 lo rc t0 shot v tmo="" port="" dir="" plo
  shift 2
  while [ $# -gt 0 ]; do
    case $1 in
      --timeout) tmo=${2:-}; shift 2;;
      --port) port=${2:-}; shift 2;;
      --dir) dir=${2:-}; shift 2;;
      --) shift; break;;
      *) err "неизвестная опция '$1' (ожидался -- перед командой)"; return 2;;
    esac
  done
  [ $# -gt 0 ] || { err "нет команды после --"; return 2; }
  case $min in ''|*[!0-9]*) err "минуты — число"; return 2;; esac
  { [ "$min" -ge 1 ] && [ "$min" -le 480 ]; } || { err "минут от 1 до 480"; return 2; }
  case ${tmo:-0} in *[!0-9]*) err "--timeout — секунды"; return 2;; esac
  case ${port:-0} in *[!0-9]*) err "--port — число"; return 2;; esac
  [ -n "$tmo" ] || tmo=$((min * 60))
  [ -n "$dir" ] || dir=$BOX/runs/$(date +%m%d-%H%M%S)-$own
  mkdir -p "$dir" || { err "не создал каталог прогона $dir"; return 2; }
  lo=$(pico_lease_owner)
  if [ -n "$lo" ] && [ "$lo" != "$own" ]; then echo "pico run: бронь pico у $lo — очки не будить"; return 21; fi
  RUN_OWN=$own; RUN_CREATED=0; [ -z "$lo" ] && RUN_CREATED=1
  PICO_LEASE_NOTE="бронь снимет run"
  trap pico_run_cleanup EXIT
  trap 'exit 130' INT TERM HUP
  cmd_lease pico "$own" "$min" "pico run: $(basename "$1")" >/dev/null || { echo "pico run: бронь pico не взята"; return 21; }
  if [ -n "$port" ]; then
    plo=$(get "$BOX/leases/port:$port.lease" owner)
    cmd_lease "port:$port" "$own" "$min" "pico run" >/dev/null || { echo "pico run: порт $port занят чужой бронью"; return 21; }
    RUN_PORT=$port; [ -z "$plo" ] && RUN_PORT_CREATED=1
  fi
  jlog pico-run-start owner "$own" minutes "$min" dir "$dir" cmd "$*"
  t0=$(date +%s)
  pico_light on
  v=$(pico_ready "$own"); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "$v"
    echo "pico run: НЕ ГОТОВО — команда не запускалась, очки погашены, брони сняты; каталог: $dir"; return 20
  fi
  echo "$v"
  pico_shot "$dir/screen-before.png" >/dev/null
  timeout 15 "$ADB" -s "$PICO" logcat -c </dev/null >/dev/null 2>&1
  # парковка карточки границы — только автопрогону и не человеку (PICO_PARK_OK видит pico start внутри команды)
  local park=1; pico_is_human "$own" && park=0
  PICO_PARK_OK=$park PICO_SERIAL=$PICO PICO_RUN_DIR=$dir BOX_OWNER=$own BOX_CTL=$(readlink -f "$0") timeout "$tmo" "$@"; rc=$?
  shot=$(pico_shot "$dir/screen-after.png")
  timeout 30 "$ADB" -s "$PICO" logcat -d -v time </dev/null 2>/dev/null | tail -n 20000 >"$dir/logcat.txt"
  # после команды игра обычно остановлена (трап хозяина: force-stop) — система сразу возвращает карточку границы: это штатно,
  # не «вылезло окно». Остальные системные окна («Требуется контроллер» и т. п.) по-прежнему считаются.
  PICO_CARD_OK=1
  pico_diagnose >/dev/null
  jlog pico-run-done owner "$own" rc "$rc" sec "$(( $(date +%s) - t0 ))" res "${P_RES:-}" light "${P_LIGHT:-}" dir "$dir"
  if [ "$rc" -eq 124 ]; then
    pico_attention "$own" "прогон не уложился в ${tmo} с (timeout)" "$shot" timeout
    echo "pico run: ТАЙМАУТ ${tmo} с — команда прервана; каталог: $dir"; return 124
  fi
  if [ -n "$DIAG_WHY" ] && [ "$DIAG_KIND" != state ]; then  # во время прогона вылезло окно/стало темно
    pico_attention "$own" "после прогона: $DIAG_WHY" "$shot" "$DIAG_KIND"
    echo "pico run: команда rc=$rc, НО после неё на очках: $DIAG_WHY; каталог: $dir"
    [ "$rc" -eq 0 ] && return 20
    return "$rc"
  fi
  echo "pico run: ОК — команда rc=$rc за $(( $(date +%s) - t0 )) с; окно $P_RES; каталог: $dir"
  return "$rc"
}

cmd_pico() {
  local act=${1:-status} own st lo min note
  [ $# -gt 0 ] && shift
  case $act in
    status)
      st=$(pico_state); lo=$(pico_lease_owner)
      if [ "${st%% *}" = "?" ]; then echo "очки: не отвечают на adb (отключены? $PICO)"; return 1; fi
      if [ "${st%% *}" = Asleep ] && [ "${st##* }" = OFF ]; then
        echo "очки: Asleep, экран OFF${lo:+; бронь: $lo}"
      elif [ -n "$lo" ]; then
        echo "очки: ${st%% *} (экран ${st##* }); бронь: $lo до $(hm "$(get "$BOX/leases/pico.lease" until)")"
      else
        local since
        since=$(cat "$BOX/pico.awake-since" 2>/dev/null || echo "$NOW")
        echo "очки: ${st%% *} (экран ${st##* }) БЕЗ БРОНИ уже $(( (NOW - since) / 60 )) мин — риск выгорания матриц: pico sleep <владелец> или pico wake <владелец> <мин>"
        return 1
      fi ;;
    wake)
      [ $# -ge 2 ] || { err "использование: pico wake <владелец> <минут> [заметка…]"; return 2; }
      own=$1; min=$2; shift 2; note="$*"
      pico_unpark_card  # остаток парковки прошлого прогона не должен достаться этому владельцу
      # продление без заметки не затирает прежнюю
      [ -n "$note" ] || note=$(get "$BOX/leases/pico.lease" note)
      cmd_lease pico "$own" "$min" "${note:-очки разбужены}" || return 1
      st=$(pico_state)
      case ${st%% *} in
        Awake) echo "очки: уже Awake (экран ${st##* }) — не нажимаю POWER";;
        Asleep|Dozing)
          pico_power
          if pico_wait Awake 8; then echo "очки: Awake"; else err "очки не проснулись за 8 с (состояние: $(pico_state))"; return 1; fi
          jlog pico-wake owner "$own" minutes "$min" note "$note";;
        *) err "очки: состояние неизвестно ($st) — бронь взята, POWER не нажимал"; return 1;;
      esac ;;
    sleep)
      [ $# -ge 1 ] || { err "использование: pico sleep <владелец> [--force]"; return 2; }
      own=$1; lo=$(pico_lease_owner)
      if [ -n "$lo" ] && [ "$lo" != "$own" ] && [ "${2:-}" != "--force" ]; then
        echo "бронь pico у $lo — гасить может хозяин (--force: только по договорённости с ним)"; return 1
      fi
      if pico_sleep_now; then
        [ "$lo" = "$own" ] && cmd_release pico "$own" >/dev/null
        rm -f "$BOX/pico.awake-since"
        jlog pico-sleep owner "$own"
        echo "очки: Asleep, экран OFF${lo:+; бронь $lo снята}"
      else
        err "очки не погасли ($(pico_state)) — посмотреть вручную, не повторять POWER вслепую"; return 1
      fi ;;
    guard)
      # Для таймера раз в минуту (pico guard-install ставит юнит): Awake без брони дольше $PICO_GRACE секунд — гасим.
      st=$(pico_state); lo=$(pico_lease_owner)
      if [ "${st%% *}" != Awake ] || [ -n "$lo" ]; then rm -f "$BOX/pico.awake-since"; return 0; fi
      [ -f "$BOX/pico.awake-since" ] || { echo "$NOW" >"$BOX/pico.awake-since"; return 0; }
      since=$(cat "$BOX/pico.awake-since")
      if [ $((NOW - since)) -ge "$PICO_GRACE" ]; then
        if pico_sleep_now; then
          rm -f "$BOX/pico.awake-since"; jlog pico-guard-sleep idle_sec "$((NOW - since))"
          echo "guard: очки без брони $(( (NOW - since) / 60 )) мин — погашены"
        else
          jlog pico-guard-fail state "$(pico_state)"; echo "guard: очки не погасли" >&2; return 1
        fi
      fi ;;
    taps)
      # Выключатель нажатий `pico ready`: по умолчанию выключено — нажимать кнопки в системных окнах очков владельца
      # может только он сам (ТЗ, «Нельзя»); включает/выключает его слово через `box.sh pico taps on|off`.
      case ${1:-status} in
        on) : >"$BOX/pico-ready.taps"; jlog pico-taps on 1; echo "pico ready: нажатия белого списка ВКЛЮЧЕНЫ";;
        off) rm -f "$BOX/pico-ready.taps"; jlog pico-taps off 1; echo "pico ready: нажатия выключены (только чтение и вердикт)";;
        status) [ -f "$BOX/pico-ready.taps" ] && echo "pico ready: нажатия включены" || echo "pico ready: нажатия выключены";;
        *) err "pico taps on|off|status"; return 2;;
      esac ;;
    ready)
      # идемпотентно: бронь не снимает, очки не гасит при успехе; при НЕ ГОТОВО — гасит (как и раньше), бронь остаётся
      [ $# -ge 1 ] || { err "использование: pico ready <владелец брони>"; return 2; }
      own=$1; pico_ready "$own"; return $? ;;
    start)
      [ $# -ge 2 ] || { err "использование: pico start <владелец брони> <пакет/активити>"; return 2; }
      [ "$(pico_lease_owner)" = "$1" ] || { echo "pico start: нет брони pico у $1"; return 1; }
      pico_start "$1" "$2"; return $? ;;
    unpark)
      # вернуть карточку границы на дисплей 0 (если её парковали); безвредно без парковки
      pico_unpark_card
      [ -f "$BOX/pico-parked.stack" ] && { echo "карточка всё ещё запаркована (очки недоступны по adb?): $(cat "$BOX/pico-parked.stack")"; return 1; }
      echo "карточка границы на месте (не запаркована)";;
    fg)
      # что на переднем плане и в каком состоянии очки: «окно=… light=… граница=… трекинг=… вердикт=ok|причина»; код 0 — здоровое
      st=$(pico_state)
      if [ "${st%% *}" != Awake ]; then echo "очки: ${st%% *} — окно не читается (Asleep: свойства устарели)"; return 1; fi
      if pico_diagnose; then
        echo "окно=$P_RES light=${P_LIGHT:-?} граница=${P_BOUND:-?} трекинг=${P_ALG:-?}/${P_CONF:-?} вердикт=ok"
      else
        echo "окно=${P_RES:-?} light=${P_LIGHT:-?} граница=${P_BOUND:-?} трекинг=${P_ALG:-?}/${P_CONF:-?} вердикт=$DIAG_KIND: $DIAG_WHY"; return 1
      fi ;;
    run) pico_run "$@"; return $? ;;
    *) err "pico status | wake <владелец> <мин> [заметка] | sleep <владелец> [--force] | guard | ready <владелец> | start <владелец> <пакет/активити> | unpark | fg | run <владелец> <мин> [--timeout сек] [--port N] [--dir каталог] -- команда… | taps on|off|status"; return 2;;
  esac
}

# --- экземпляры служб на сессию (D3) -----------------------------------------------------------------------------------------
# `up <служба> <сессия> -- команда…`: свой каталог ~/box/inst/<служба>-<сессия>, порт из пула (бронь port:N), отвязанный процесс, лог.
# Нужно, чтобы сессии не делили 7777/2517/4174 и не затирали друг другу каталоги. Команда сама решает, что запускать
# (сервер стенда Godot, копия коллектора со своей БД, статика): в аргументах подставляются {PORT} и {DIR}, в окружении —
# BOX_PORT и BOX_DIR. Чужое не трогаем: down убивает только процесс, записанный в этом экземпляре, и только если время его
# старта совпало (после перезагрузки pid мог достаться другому).
INST=$BOX/inst
POOL_LO=${BOX_POOL_LO:-7800}
POOL_HI=${BOX_POOL_HI:-7899}
port_in_use() { ss -H -ltn "sport = :$1" 2>/dev/null | grep -q . || ss -H -lun "sport = :$1" 2>/dev/null | grep -q .; }
port_leased_by_other() { # port_leased_by_other <порт> <сессия> → 0, если на port:<порт> действующая бронь не этой сессии
  local f=$BOX/leases/port:$1.lease cur until
  [ -f "$f" ] || return 1
  cur=$(get "$f" owner); until=$(get "$f" until)
  [ "${until:-0}" -gt "$NOW" ] && [ "$cur" != "$2" ]
}
inst_alive() { # inst_alive <каталог> → 0, если записанный процесс жив и это тот же процесс (время старта совпало)
  local d=$1 pid st
  pid=$(get "$d/inst" pid); st=$(get "$d/inst" lstart)
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ "$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/  */ /g')" = "$st" ]
}
valid_name() { # имя сессии бывает кириллицей (Дронкарта): запрещаем только то, что ломает путь, кавычки и разбор
  case $1 in ''|-*|.*|*/*|*..*|*[[:space:]]*|*[[:cntrl:]]*|*[\"\'\\\$\`\;\&\|\<\>\*\?\(\)\{\}]*) return 1;; esac
  return 0
}

cmd_up() {
  [ $# -ge 3 ] || { err "использование: up <служба> <сессия> [--port N] [--ttl мин] -- команда… ({PORT}, {DIR} подставляются)"; return 2; }
  local svc=$1 ses=$2 port="" ttl=480 d i a
  shift 2
  while [ $# -gt 0 ]; do
    case $1 in
      --port) port=${2:-}; shift 2;;
      --ttl) ttl=${2:-480}; shift 2;;
      --) shift; break;;
      *) err "ожидался -- перед командой (получено '$1')"; return 2;;
    esac
  done
  [ $# -gt 0 ] || { err "нет команды после --"; return 2; }
  valid_name "$svc" && valid_name "$ses" || { err "имена службы и сессии: без пробелов, /, кавычек и спецсимволов оболочки"; return 2; }
  d=$INST/$svc-$ses
  if [ -f "$d/inst" ] && inst_alive "$d"; then
    echo "up: $svc/$ses уже запущен — pid $(get "$d/inst" pid), порт $(get "$d/inst" port), каталог $d"; return 0
  fi
  (
    flock 7  # выбор порта и бронь — под одним замком, иначе две сессии возьмут один порт
    if [ -n "$port" ]; then
      case $port in ''|*[!0-9]*) err "порт — число"; exit 2;; esac
      if port_in_use "$port" || port_leased_by_other "$port" "$ses"; then err "порт $port занят (процесс или бронь) — box.sh queue / leases"; exit 1; fi
    else
      for ((i = POOL_LO; i <= POOL_HI; i++)); do
        port_in_use "$i" && continue
        port_leased_by_other "$i" "$ses" && continue
        port=$i; break
      done
      [ -n "$port" ] || { err "в пуле $POOL_LO–$POOL_HI нет свободного порта"; exit 1; }
    fi
    cmd_lease "port:$port" "$ses" "$ttl" "экземпляр $svc" >/dev/null || exit 1
    echo "$port" >"$BOX/locks/.last-port"
  ) 7>"$BOX/locks/inst.lock" || return $?
  port=$(cat "$BOX/locks/.last-port")
  mkdir -p "$d"
  local args=()
  for a in "$@"; do a=${a//\{PORT\}/$port}; a=${a//\{DIR\}/$d}; args+=("$a"); done
  (
    cd "$d" || exit 1
    export BOX_PORT=$port BOX_DIR=$d
    setsid nohup "${args[@]}" >"$d/log" 2>&1 </dev/null 7>&- 9>&- &
    echo $! >"$d/.pid"
  )
  local pid
  pid=$(cat "$d/.pid"); rm -f "$d/.pid"
  sleep 2
  if ! kill -0 "$pid" 2>/dev/null; then
    cmd_release "port:$port" "$ses" >/dev/null
    err "up: $svc/$ses не запустился (процесс завершился за 2 с) — журнал: $d/log"; tail -n 5 "$d/log" >&2
    jlog inst-fail svc "$svc" ses "$ses" port "$port"; return 1
  fi
  {
    echo "service=$svc"; echo "session=$ses"; echo "pid=$pid"; echo "port=$port"; echo "since=$NOW"
    echo "lstart=$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/  */ /g')"; echo "cmd=$(clean "${args[*]}")"
  } >"$d/inst"
  jlog inst-up svc "$svc" ses "$ses" port "$port" pid "$pid"
  echo "up: $svc/$ses — pid $pid, порт $port, каталог $d, журнал $d/log"
}

cmd_down() {
  [ $# -ge 2 ] || { err "использование: down <служба> <сессия> [--purge]"; return 2; }
  local svc=$1 ses=$2 d pid port i
  d=$INST/$svc-$ses
  [ -f "$d/inst" ] || { echo "down: экземпляра $svc/$ses нет"; return 0; }
  pid=$(get "$d/inst" pid); port=$(get "$d/inst" port)
  if inst_alive "$d"; then
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
    for ((i = 0; i < 8; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    if kill -0 "$pid" 2>/dev/null; then kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null; fi
    echo "down: $svc/$ses остановлен (pid $pid)"
  else
    echo "down: процесс $svc/$ses уже не идёт"
  fi
  rm -f "$d/inst"
  cmd_release "port:$port" "$ses" >/dev/null 2>&1
  jlog inst-down svc "$svc" ses "$ses" port "$port"
  [ "${3:-}" = "--purge" ] && rm -rf "$d"
  return 0
}

cmd_inst_ls() {
  local d any=0 svc ses
  for d in "$INST"/*/; do
    [ -f "$d/inst" ] || continue
    svc=$(get "$d/inst" service); ses=$(get "$d/inst" session); any=1
    if inst_alive "$d"; then
      echo "$svc/$ses: идёт, pid $(get "$d/inst" pid), порт $(get "$d/inst" port), с $(hm "$(get "$d/inst" since)"), каталог ${d%/}"
    else
      echo "$svc/$ses: НЕ ИДЁТ (процесс пропал), порт $(get "$d/inst" port), журнал ${d%/}/log — down, затем up"
    fi
  done
  [ "$any" -eq 1 ] || echo "экземпляров нет"
}

# --- лишние adb-серверы и возврат устройств (инцидент 14.10) -------------------------------------------------------------------
# Второй adb-сервер (не 5037) забирает USB-устройства себе, основной их не видит (ни device, ни unauthorized). Так очки пропали
# после перезагрузки: `adb -L tcp:5099` поднимала переменная ANDROID_ADB_SERVER_PORT=5099 у Godot (любая adb-команда сама стартует сервер).
adb_servers() { # строки «порт pid клиентов» для adb-серверов НЕ на 5037 (клиенты — установленные соединения на порт сервера)
  local pid port cl
  # процесс — сервер adb, если в args есть «fork-server» или «server nodaemon»; порт — из «-L tcp:[localhost:]N» (так их стартует
  # ANDROID_ADB_SERVER_PORT) или «-P N»; `timeout …`-обёртки и сам awk пропускаем (там adb не первый аргумент команды).
  ps -eo pid=,args= 2>/dev/null | awk '$2 ~ /(^|\/)adb$/ && /(fork-server|server nodaemon)/ {
      if (match($0, /-L tcp:(localhost:)?[0-9]+/)) { s = substr($0, RSTART, RLENGTH); sub(/.*:/, "", s) }
      else if (match($0, /-P [0-9]+/)) { s = substr($0, RSTART + 3, RLENGTH - 3) }
      else next
      if (s != "5037") print $1, s }' |
  while read -r pid port; do
    cl=$(ss -Htn state established "( sport = :$port )" 2>/dev/null | wc -l | tr -d ' ')
    echo "$port $pid $cl"
  done
}
adb_stray_text() { # одной строкой для вердикта; пусто — лишних нет
  adb_servers | awk '{printf "adb-сервер на порту %s (pid %s, клиентов %s); ", $1, $2, $3}'
}
cmd_adb_rescue() { # adb-rescue [--dry]: остановить лишние серверы без клиентов, вернуть устройства основному, восстановить forward/reverse
  local dry=0 s port pid cl serial fw rv killed=0 dev l r
  [ "${1:-}" = "--dry" ] && dry=1
  s=$(adb_servers)
  if [ -z "$s" ]; then echo "adb rescue: лишних adb-серверов нет"; return 0; fi
  while read -r port pid cl; do
    [ -n "$port" ] || continue
    if [ "$cl" -gt 0 ]; then
      echo "adb rescue: порт $port (pid $pid): есть клиенты ($cl) — НЕ трогаю, договоритесь с хозяином"; continue
    fi
    echo "adb rescue: порт $port (pid $pid) без клиентов — $([ "$dry" = 1 ] && echo "остановил бы" || echo "останавливаю")"
    if [ "$dry" = 0 ]; then
      ANDROID_ADB_SERVER_PORT=$port "$ADB" kill-server </dev/null >/dev/null 2>&1
      jlog adb-stray-killed port "$port" pid "$pid"
      killed=$((killed + 1))
    fi
  done <<<"$s"
  [ "$dry" = 1 ] && return 0
  [ "$killed" -gt 0 ] || return 1
  sleep 4
  # основной сервер опрашивает USB только при старте: если устройство Pico есть в USB, а в adb нет — один перезапуск службы,
  # перед ним записываем forward/reverse всех устройств и возвращаем точно такими же (порядок reverse: «удалённый локальный»).
  if lsusb 2>/dev/null | grep -q '2d40:' && ! "$ADB" devices 2>/dev/null | grep -q "^${PICO}[[:space:]]"; then
    fw=$("$ADB" forward --list 2>/dev/null | awk 'NF>=3{print $1, $2, $3}')
    rv=""
    for dev in $("$ADB" devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1}'); do
      l=$(timeout 8 "$ADB" -s "$dev" reverse --list </dev/null 2>/dev/null | awk -v d="$dev" 'NF>=3{print d, $2, $3}')
      [ -n "$l" ] && rv="$rv$l"$'\n'
    done
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
    export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
    systemctl --user restart box-adb
    for r in 1 2 3 4 5 6 7 8 9 10 11 12; do sleep 1; "$ADB" devices 2>/dev/null | grep -q "^${PICO}[[:space:]]" && break; done
    while read -r serial l r; do
      [ -n "$serial" ] && "$ADB" -s "$serial" forward "$l" "$r" </dev/null >/dev/null 2>&1
    done <<<"$fw"
    while read -r serial r l; do
      [ -n "$serial" ] && "$ADB" -s "$serial" reverse "$r" "$l" </dev/null >/dev/null 2>&1
    done <<<"$rv"
    jlog adb-restart-claim note "box-adb перезапущен после остановки лишнего сервера; forward/reverse восстановлены" fw "$(wc -l <<<"$fw" | tr -d ' ')" rv "$(printf '%s' "$rv" | grep -c .)"
  fi
  "$ADB" devices -l 2>&1 | sed -n '1,6p'
}

sub=${1:-}
[ $# -gt 0 ] && shift
case $sub in
  up) cmd_up "$@";;
  down) cmd_down "$@";;
  inst) cmd_inst_ls;;
  pico) cmd_pico "$@";;
  adb-rescue) cmd_adb_rescue "$@";;
  adb-stray) adb_stray_text;;
  lease) cmd_lease "$@";;
  release) cmd_release "$@";;
  leases) cmd_leases;;
  check) cmd_check "$@";;
  run) cmd_run "$@";;
  queue) cmd_queue "$@";;
  *) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 2;;
esac
