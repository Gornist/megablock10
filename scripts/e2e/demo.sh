#!/bin/bash
# Демо-ролик для стейкхолдеров: экран Alice, ≈3–4 минуты. Записывает screenrecord'ом эмулятора A, затем ffmpeg ускоряет запись до 2 минут
# и делает demo.mp4 (+ gif). Требует свежего стенда (./up.sh): сюжет двигает предметы и деньги, повторный прогон без up.sh даст дубли.
#   ./demo.sh                 — всё: подготовка, запись, обработка
#   SCENES="breach shard finale" ./demo.sh   — только перечисленные сцены (для отладки, без записи если NOREC=1)
#
# Сюжет: Bob предлагает Alice сделку по узлу «Арасака-404» (100 эдди сразу, 300 — за добытые шарды, плюс демон BLACKOUT против тревоги СБ) →
# Alice соглашается, ломает узел (пошаговый взлом, реплики ICE, майнер, подавленная тревога), извлекает зашифрованный шард, расшифровывает
# демоном-дешифратором, читает странную документацию на кибер-тело, пишет Bob и передаёт шард → Bob платит ещё 300 → неизвестный пишет «Мы знаем».
source "$(dirname "$0")/lib.sh"
OUT=$E2E_DIR/demo; mkdir -p "$OUT"
PKA=$(cat "$E2E_DIR/pk_$A.txt"); PKB=$(cat "$E2E_DIR/pk_$B.txt")
SCENES=${SCENES:-"deal deck breach shard finale wallet outro"}
step() { log "▶ $*"; }
say_b() { dbg $B DEBUG_SET --es say "$PKA|$1"; }
say_a() { dbg $A DEBUG_SET --es say "$PKB|$1"; }
# Y=2300 у TAB_CHAT/TAB_DECK — пересчитан под новую высоту MbAppShell (52 dp вместо ≈62dp, docs/ux/ui-migration-plan.md,
# M3), но не проверен на живом эмуляторе (посчитан по dp, не измерен) — если тап промахивается, подвиньте Y по записи.
# Нижнее меню в новой оболочке видно всегда, даже из треда/взлома (так в прототипе) — «назад» ниже не обязателен для
# переключения вкладки, но сцены его всё равно делают: так исходный экран сцены предсказуем независимо от смены оболочки.
TAB_CHAT="135 2300"; TAB_DECK="675 2300"; BACK="55 130"
tap() { adb_ $A shell input tap $1; }
tapt() { local i; for i in 1 2 3; do tap_text $A "$1" >/dev/null && return 0; sleep 1; done; log "не нашёл «$1»"; }

make_qr() {
  QR=$(api POST /api/master/containers "$(python3 - <<PY
import json
print(json.dumps({"id":"arasaka-404-$RANDOM","name":"Арасака-404","tier":"HARD","ownerFaction":"Arasaka","slots":[
 {"type":"SHARD","tier":"HARD","copies":1,"shard":{"title":"Спецификация «Кибер-тело К-7»","meta":"Arasaka · закрытый отдел · часть 3 из 9","valueHint":"ценность: неизвестна, но за неё убьют","body":"К-7 // силовая рама: сплав титан-керамика, привод плеча 4,2 кН·м.\nВооружение: два интегрированных рельсовых орудия, ракетный ярус на 12 боеголовок, встроенный ЭМИ-подавитель.\nУправление: нейроинтерфейс без предохранителей. Оператор не должен быть в сознании.\nПримечание: испытуемый №7 не вернулся.","decryptAction":True,"moneyAmount":0}}]}))
PY
)" | jq_ 'd["qr"]')
}

prepare() {
  step "подготовка"
  dbg $A DEBUG_SET --es balance 250; dbg $B DEBUG_SET --es balance 900; dbg $A DEBUG_SET --es ram 9
  dbg $A DEBUG_SET --es daemon "Cipher Key:7A,E9:2:DECRYPT"
  dbg $A DEBUG_SET --es daemon "Deep Miner:E9,FF:2:MINER"
  dbg $A DEBUG_SET --es daemon "Data Siphon:1C,FF:2:EXTRACT_SHARD"
  dbg $B DEBUG_SET --es daemon "Black Curtain:7A,BD:2:BLACKOUT"
  set_config $A clock 1; set_config $A timer 4; set_config $A autosolve true; set_config $A step 900
  dbg $A DEBUG_SET --es cooldowns reset
  make_qr
  restart_app $A; sleep 8
  for i in 1 2 3; do "$(dirname "$0")/link.sh" && break; sleep 5; done
}

scene_container() { dbg $A DEBUG_SET --es cooldowns reset; make_qr; }

scene_deal() {
  step "сцена: сделка"
  tapt "Чат" 2>/dev/null; sleep 1
  say_b "Слушай, Alice. Есть работа: узел «Арасака-404»."; sleep 2
  say_b "100 эдди сразу. 300 — когда пришлёшь добытые шарды."; sleep 2
  say_b "Отдам демона Black Curtain — он глушит тревогу СБ Арасаки."; sleep 2
  tapt "Bob"; sleep 2
  say_a "Согласна. Присылай демона."; sleep 2
  dbg $B DEBUG_SET --es pay "$PKA:100:online"; sleep 4
  tapt "Принять"; sleep 3
  dbg $B DEBUG_SET --es give "daemon:debug-Black Curtain:$PKA"; sleep 4
  tapt "Принять"; sleep 3
  tap "$BACK"; sleep 1.5
}

# Обзор интерфейса перед взломом: список демонов с эффектами и ценой в ячейках буфера, пустой список шардов.
scene_deck() {
  step "сцена: Кибердека"
  tap "$TAB_DECK"; sleep 4                     # плотный список демонов: имя, коды, эффект и цена в ячейках буфера; справа внизу FAB «Сканировать»
  tapt "Data Siphon"; sleep 3                  # тап по строке раскрывает её: появляется «Передать другому игроку»
  tapt "Data Siphon"; sleep 2                  # и сворачивает
  tapt "Шарды"; sleep 4
  tapt "Демоны"; sleep 2
}

scene_breach() {
  step "сцена: взлом"
  dbg $A DEBUG_QR --es qr "$QR"; sleep 4      # скан QR узла → выбор демонов; вверху буфер, он заполняется кодами выбранных демонов
  tapt "Data Siphon"; sleep 2; tapt "Black Curtain"; sleep 2
  tapt "Deep Miner"; sleep 3
  tapt "Взломать контейнер"
  sleep 24                       # вход в узел, таймер, реплики ICE, сетка решается по клетке — всё на одном экране без прокрутки
  sleep 9                        # итог оверлеем поверх экрана: шард, эдди, сигнал СБ
  tapt "Новый контейнер"; sleep 2 # оверлей закрыт — обратно к списку Кибердеки
}

scene_shard() {
  step "сцена: шард"
  tapt "Шарды"; sleep 3
  tapt "Кибер-тело"; sleep 9     # шард зашифрован: набор символов, подсказка про дешифратор
  tapt "Расшифровать"; sleep 3
  wait_until 60 screen_has $A "силовая рама"   # шифр-замок решает автосолвер, затем открывается текст
  sleep 9                                       # читаем расшифрованный текст
  adb_ $A shell input swipe 540 1500 540 1000 900; sleep 4
  tapt "Назад к шардам"; sleep 2
}

scene_finale() {
  step "сцена: финал"
  tap "$TAB_CHAT"; sleep 2; tapt "Bob"; sleep 2
  say_a "Всё сделала. В шарде документация на кибер-тело для тяжёлого киборга. Очень странная."; sleep 4
  tap "$BACK"; sleep 1.5; tap "$TAB_DECK"; sleep 2
  tapt "Шарды"; sleep 1.5; tapt "Кибер-тело"; sleep 2
  tapt "Передать другому игроку"; sleep 2; tapt "Bob"; sleep 3
  tap "$TAB_CHAT"; sleep 2; tapt "Bob"; sleep 2
  back_if_arrow $B; sleep 1; adb_ $B shell input tap 135 2300; sleep 1     # Bob (за кадром): из треда в список → вкладка «Чат»
  tap_text $B "Alice" >/dev/null || log "B: не нашёл Alice"; sleep 2; tap_text $B "Принять" >/dev/null || log "B: не нашёл Принять (шард)"; sleep 2   # принимает шард
  say_b "Отличная работа, Alice. Держи обещанные 300."; sleep 2
  dbg $B DEBUG_SET --es pay "$PKA:300:online"; sleep 4
  tapt "Принять"; sleep 4   # A принимает 300
}

# Финальный штрих отдельным куском: из треда в список чатов и на глазах приходит сообщение от неизвестного.
# Экран «Финансы»: баланс и журнал операций после всей истории.
scene_wallet() {
  step "сцена: Финансы"
  back_if_arrow $A; sleep 2
  tap "945 2300"; sleep 8
  adb_ $A shell input swipe 540 1700 540 900 1000; sleep 4
}

scene_outro() {
  step "сцена: финальный штрих"
  tap "$TAB_CHAT"; sleep 3       # в списке чатов; строки бесед подгружаются не сразу
  dbg $B DEBUG_SET --es sayas "$PKA|UNKNOWN-DEMO-KEY|Аноним|?|Мы знаем."; sleep 9
}

# ── Запись по сценам: screenrecord ограничен 180 с, а каждый тап по тексту на эмуляторе стоит секунды, поэтому каждая сцена — свой
#    кусок, а ffmpeg склеивает их с разной скоростью (решение сетки — быстро, чтение чата — помедленнее) так, чтобы вышло ≈2 минуты.
rec_start() {
  adb_ $A shell rm -f /sdcard/seg_$1.mp4
  adb_ $A shell "screenrecord --size 540x1200 --bit-rate 3000000 --time-limit 170 /sdcard/seg_$1.mp4" &
  RECPID=$!; sleep 1.5
}
rec_stop() {
  adb_ $A shell "pkill -2 screenrecord" >/dev/null 2>&1; wait $RECPID 2>/dev/null; sleep 2
  adb_ $A pull /sdcard/seg_$1.mp4 "$OUT/seg_$1.mp4" >/dev/null
}
trim_of() { case $1 in deal) echo 3.5;; *) echo 0;; esac; }   # мёртвое начало первой сцены (ждём первого сообщения)
cutend_of() { case $1 in finale) echo 0.4;; *) echo 0;; esac; }
speed_of() { case $1 in deal) echo 1.3;; finale) echo 1.5;; *) echo 1.0;; *) echo 1.5;; esac; }
compose() {
  local total=0 s d
  for s in $SCENES; do d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/seg_$s.mp4"); total=$(python3 -c "print($total+($d-$(trim_of $s))/$(speed_of $s))"); done
  local n; n=$(echo $SCENES | wc -w)
  local k=1.0
  [ -n "$TARGET" ] && k=$(python3 -c "print(max(1.0, round($total/($TARGET-2.5*$n), 3)))")   # TARGET=120 — ужать до ~2 минут
  log "после ускорения по сценам ≈${total%.*} с → общий множитель ×$k"
  : > "$OUT/list.txt"
  for s in $SCENES; do
    # screenrecord пишет кадры только при изменении экрана: последнее состояние куска получило бы нулевую длину — держим его 2.5 с
    # финальный тап сцены (список чатов) отрезаем: тот же переход покажет следующая сцена
    local dur; dur=$(python3 -c "print(max(1, $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/seg_$s.mp4") - $(trim_of $s) - $(cutend_of $s)))")
    ffmpeg -v error -y -ss "$(trim_of $s)" -t "$dur" -i "$OUT/seg_$s.mp4" -vf "setpts=PTS/$(python3 -c "print($(speed_of $s)*$k)"),fps=30,tpad=stop_mode=clone:stop_duration=2.5" -c:v libx264 -crf 23 -preset medium -pix_fmt yuv420p "$OUT/enc_$s.mp4"
    echo "file 'enc_$s.mp4'" >> "$OUT/list.txt"
  done
  ffmpeg -v error -y -f concat -safe 0 -i "$OUT/list.txt" -c copy -movflags +faststart "$OUT/demo.mp4"
  ffmpeg -v error -y -i "$OUT/demo.mp4" -vf "fps=8,scale=360:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer" "$OUT/demo.gif"
  ls -la "$OUT/demo.mp4" "$OUT/demo.gif"; ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/demo.mp4"
}

[ -n "$RECOMPOSE" ] && { compose; exit 0; }   # пересобрать ролик из уже записанных кусков
if [ -z "$NOREC" ] && [ -z "$SKIPPREP" ]; then prepare; fi
# NOVIDEO=1 — прогнать сюжет ради данных на дашборде (например, для dashboard-demo.mjs), без записи экрана телефона и монтажа.
RECORDING=1; { [ -n "$NOREC" ] || [ -n "$NOVIDEO" ]; } && RECORDING=""
for s in $SCENES; do
  if [ -n "$RECORDING" ]; then rec_start $s; fi
  scene_$s
  if [ -n "$RECORDING" ]; then rec_stop $s; fi
done
if [ -n "$RECORDING" ]; then compose; fi
