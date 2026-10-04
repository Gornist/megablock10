#!/bin/bash
set -e

# Скрипт управления Pico 4 без интернета: установка APK, запуск, сбор журналов, снимки экрана, информация об устройстве.
# Использование: pico.sh <команда> [аргумент]
# Команды: install <apk>, launch, stop, log, shot, info, tune

# Имя пакета из netrun/export_presets.cfg
PACKAGE="com.megablok10.netrun"

# Выбор устройства: переменная PICO_SERIAL или единственное подключённое
select_device() {
  if [[ -n "$PICO_SERIAL" ]]; then
    echo "$PICO_SERIAL"
    return
  fi

  local devices
  devices=$(adb devices | grep -E '^\S+\s+device$' | awk '{print $1}')
  local count
  count=$(echo "$devices" | wc -l)

  if [[ $count -eq 0 ]]; then
    echo "Ошибка: устройство не подключено" >&2
    return 1
  elif [[ $count -gt 1 ]]; then
    echo "Ошибка: подключено несколько устройств. Выберите через PICO_SERIAL:" >&2
    echo "$devices" | sed 's/^/  /' >&2
    return 1
  fi

  echo "$devices"
}

# Справка
show_help() {
  cat <<'EOF'
Управление Pico 4 без интернета.

Использование: pico.sh <команда> [аргумент]

Команды:
  install <apk>    Установить APK на устройство
  launch           Запустить приложение
  stop             Остановить приложение
  log              Забрать журнал приложения и logcat в каталог с датой
  shot             Снимок экрана в файл (дата и время в имени)
  info             Модель, прошивка, заряд, Wi-Fi SSID и IP
  tune [ключ=значение ...]   Настройки комфорта (user://comfort.cfg на очках): показать, изменить, перезапустить приложение,
                   напечатать строку `comfort` из журнала. `tune --reset` — удалить файл (значения по умолчанию)

Переменная окружения:
  PICO_SERIAL      Serial устройства (если не задана, используется единственное подключённое)

Примеры:
  pico.sh install netrun-client.apk
  pico.sh launch
  pico.sh log
  pico.sh shot
  pico.sh info
  pico.sh tune turn_speed_deg_s=45 teleport_range=3.5
  pico.sh tune --reset
EOF
}

# install <apk>
cmd_install() {
  local apk="$1"
  if [[ -z "$apk" ]]; then
    echo "Ошибка: укажите путь к APK" >&2
    return 1
  fi
  if [[ ! -f "$apk" ]]; then
    echo "Ошибка: файл $apk не найден" >&2
    return 1
  fi

  local serial
  serial=$(select_device) || return 1

  echo "Установка $apk на $serial..."
  adb -s "$serial" install -r "$apk"
  echo "Готово."
}

# launch
cmd_launch() {
  local serial
  serial=$(select_device) || return 1

  echo "Запуск $PACKAGE на $serial..."
  # Точка входа шаблона Godot 4.7 — псевдоним com.godot.game.GodotAppLauncher (прежние .MainActivity и
  # com.godotengine.godot.GodotApp не существуют, а `am start` об ошибке кодом выхода не сообщает).
  # Аргументы через `--esa command_line_params` сюда не передать: Godot снимает их у экспортированной активности,
  # адрес и токен — только в export_presets.cfg, command_line/extra_args (netrun/README.md, «Pico 4»).
  local out
  out=$(adb -s "$serial" shell am start -S -n "$PACKAGE/com.godot.game.GodotAppLauncher" 2>&1)
  echo "$out"
  if grep -qE "Error|Exception|not started" <<<"$out"; then
    echo "Ошибка: приложение не запущено (не установлено? поверх — диалог системы очков?)" >&2
    return 1
  fi
  echo "Приложение запущено."
}

# stop
cmd_stop() {
  local serial
  serial=$(select_device) || return 1

  echo "Остановка $PACKAGE на $serial..."
  adb -s "$serial" shell am force-stop "$PACKAGE"
  echo "Приложение остановлено."
}

# log
cmd_log() {
  local serial
  serial=$(select_device) || return 1

  local logdir
  logdir="pico-logs-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$logdir"

  echo "Сбор логов в $logdir..."

  # Журнал приложения: user://logs — на Android это внутренняя память приложения (files/logs), не /sdcard;
  # читается через run-as (только отладочная сборка — артефакт CI и экспорт --export-debug).
  echo "Забираем журнал приложения (run-as $PACKAGE, files/logs)..."
  mkdir -p "$logdir/app-logs"
  local f n=0
  for f in $(adb -s "$serial" shell run-as "$PACKAGE" ls files/logs 2>/dev/null | tr -d '\r'); do
    adb -s "$serial" exec-out run-as "$PACKAGE" cat "files/logs/$f" > "$logdir/app-logs/$f" && n=$((n + 1))
  done
  echo "Журнал приложения: $logdir/app-logs/ (файлов: $n)"

  # logcat в файл
  echo "Забираем logcat..."
  adb -s "$serial" logcat -d > "$logdir/logcat.log"
  echo "Logcat: $logdir/logcat.log"

  echo "Готово. Журналы в $logdir/"
}

# shot
cmd_shot() {
  local serial
  serial=$(select_device) || return 1

  local filename
  filename="pico-shot-$(date +%Y%m%d-%H%M%S).png"

  echo "Снимок экрана в $filename..."
  adb -s "$serial" shell screencap -p "/sdcard/$filename"
  adb -s "$serial" pull "/sdcard/$filename" "$filename"
  adb -s "$serial" shell rm "/sdcard/$filename"

  echo "Готово: $filename"
}

# info
cmd_info() {
  local serial
  serial=$(select_device) || return 1

  echo "=== Информация об устройстве ==="

  # Модель
  echo -n "Модель: "
  adb -s "$serial" shell getprop ro.product.model

  # Прошивка / версия ПО
  echo -n "Прошивка (версия ПО): "
  adb -s "$serial" shell getprop ro.build.fingerprint | cut -d'/' -f1

  echo -n "Версия OS: "
  adb -s "$serial" shell getprop ro.build.version.release

  # Заряд
  echo -n "Заряд: "
  adb -s "$serial" shell dumpsys battery | grep -E '^\s+level:' | awk '{print $2 "%"}'

  # Wi-Fi SSID и IP
  echo "Wi-Fi:"
  echo -n "  SSID: "
  adb -s "$serial" shell cmd connectivity show-wifi | grep "\"SSID\"" | head -1 | sed 's/.*"SSID": "\([^"]*\)".*/\1/' || echo "(отключен или не подключен)"

  echo -n "  IP: "
  adb -s "$serial" shell ip addr show | grep "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' | cut -d'/' -f1 || echo "(нет)"

  echo "==="
}

# Ключи comfort.cfg (netrun/client/comfort_config.gd); пределы клиент держит сам, здесь — только формат.
COMFORT_FILE="files/comfort.cfg"
COMFORT_NUM_KEYS="turn_speed_deg_s turn_vignette turn_ramp_up_s turn_ramp_down_s teleport_range teleport_cooldown teleport_blink_s"
COMFORT_KEYS="turn_mode $COMFORT_NUM_KEYS"

# Содержимое comfort.cfg на очках (пусто, если файла нет). Отладочная сборка debuggable — читается через run-as.
comfort_read() {
  adb -s "$1" exec-out run-as "$PACKAGE" cat "$COMFORT_FILE" 2>/dev/null | tr -d '\r' || true
}

# Строки `comfort` и `comfort.warn` из самого свежего журнала приложения на очках.
comfort_log_lines() {
  local serial="$1" newest
  newest=$(adb -s "$serial" shell run-as "$PACKAGE" ls -t files/logs 2>/dev/null | tr -d '\r' | head -1)
  [[ -n "$newest" ]] || return 0
  adb -s "$serial" exec-out run-as "$PACKAGE" cat "files/logs/$newest" 2>/dev/null | tr -d '\r' | grep -a -E ' comfort(\.warn)? ' || true
}

# tune [--reset | ключ=значение ...]
cmd_tune() {
  local serial
  serial=$(select_device) || return 1

  if [[ "$1" == "--reset" ]]; then
    adb -s "$serial" shell "run-as $PACKAGE rm -f $COMFORT_FILE"
    echo "comfort.cfg удалён: значения по умолчанию из кода."
  elif [[ $# -eq 0 ]]; then
    echo "--- $COMFORT_FILE на $serial ---"
    comfort_read "$serial"
    echo "--- (изменить: pico.sh tune ключ=значение ...; ключи: $COMFORT_KEYS)"
    return 0
  else
    # Текущие значения файла + изменения -> новый файл.
    declare -A vals
    local line k v
    while IFS= read -r line; do
      line="${line%%;*}"
      [[ "$line" == *=* ]] || continue
      k="$(echo "${line%%=*}" | tr -d ' ')"
      v="$(echo "${line#*=}" | sed 's/^ *//; s/ *$//')"
      [[ -n "$k" ]] && vals[$k]="$v"
    done < <(comfort_read "$serial")
    local arg
    for arg in "$@"; do
      if [[ "$arg" != *=* ]]; then
        echo "Ошибка: «$arg» — нужно ключ=значение" >&2
        return 1
      fi
      k="${arg%%=*}"
      v="${arg#*=}"
      if [[ " $COMFORT_KEYS " != *" $k "* ]]; then
        echo "Ошибка: неизвестный ключ «$k». Допустимы: $COMFORT_KEYS" >&2
        return 1
      fi
      if [[ "$k" == "turn_mode" ]]; then
        v="${v//\"/}"
        if [[ "$v" != "smooth" && "$v" != "snap" ]]; then
          echo "Ошибка: turn_mode — smooth или snap" >&2
          return 1
        fi
        v="\"$v\""
      elif ! [[ "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        echo "Ошибка: $k — число, получено «$v»" >&2
        return 1
      fi
      vals[$k]="$v"
    done
    local content="[comfort]"$'\n'$'\n'
    for k in $COMFORT_KEYS; do
      [[ -n "${vals[$k]:-}" ]] && content+="$k=${vals[$k]}"$'\n'
    done
    printf '%s' "$content" | adb -s "$serial" shell "run-as $PACKAGE sh -c 'cat > $COMFORT_FILE'"
    echo "--- записано в $COMFORT_FILE ---"
    printf '%s' "$content"
  fi

  # Перезапуск, чтобы клиент перечитал файл; ждём строку comfort в новом журнале (не дольше ~30 с).
  adb -s "$serial" shell am force-stop "$PACKAGE"
  adb -s "$serial" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  cmd_launch || return 1
  local i lines=""
  for i in $(seq 1 30); do
    sleep 1
    lines=$(comfort_log_lines "$serial")
    [[ "$lines" == *" comfort "* ]] && break
  done
  if [[ -z "$lines" ]]; then
    echo "Строки comfort в журнале нет: приложение не дошло до старта клиента (граница, режим рук, диалог системы?)." >&2
    return 1
  fi
  echo "$lines"
}

# Main
if [[ $# -eq 0 ]]; then
  show_help
  exit 0
fi

case "$1" in
  install)
    cmd_install "$2"
    ;;
  launch)
    cmd_launch
    ;;
  stop)
    cmd_stop
    ;;
  log)
    cmd_log
    ;;
  shot)
    cmd_shot
    ;;
  info)
    cmd_info
    ;;
  tune)
    shift
    cmd_tune "$@"
    ;;
  *)
    echo "Неизвестная команда: $1" >&2
    show_help
    exit 1
    ;;
esac
