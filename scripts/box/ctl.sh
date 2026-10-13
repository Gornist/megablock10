#!/usr/bin/env bash
# Брони и очереди devbox — выполняется НА devbox (из клона ~/box/repo; с Mac зовёт `scripts/box.sh lease|leases|release|check|run|queue`).
#   ctl.sh lease <ресурс> <владелец> <минут> [заметка…]  — взять или продлить бронь (1–480 мин); занято другим — отказ, код 1
#   ctl.sh release <ресурс> <владелец> [--force]         — снять бронь (чужую — только --force: хозяин машины или хозяин брони)
#   ctl.sh leases                                        — действующие брони (истёкшие убираются сами)
#   ctl.sh check <ресурс> <владелец>                     — 0: свободно или бронь своя; 1: чужая (для скриптов сессий)
#   ctl.sh run <класс> <владелец> [--wait сек] [--name имя] -- команда…  — выполнить в очереди класса; код выхода — команды, 3 — таймаут
#   ctl.sh queue [класс]                                 — кто держит и кто ждёт по классам; чужие замки (dbx.sh, gdUnit, display) тоже
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

sub=${1:-}
[ $# -gt 0 ] && shift
case $sub in
  lease) cmd_lease "$@";;
  release) cmd_release "$@";;
  leases) cmd_leases;;
  check) cmd_check "$@";;
  run) cmd_run "$@";;
  queue) cmd_queue "$@";;
  *) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 2;;
esac
