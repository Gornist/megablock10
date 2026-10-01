#!/bin/bash
set -e

# Скрипт управления Pico 4 без интернета: установка APK, запуск, сбор журналов, снимки экрана, информация об устройстве.
# Использование: pico.sh <команда> [аргумент]
# Команды: install <apk>, launch, stop, log, shot, info

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

Переменная окружения:
  PICO_SERIAL      Serial устройства (если не задана, используется единственное подключённое)

Примеры:
  pico.sh install netrun-client.apk
  pico.sh launch
  pico.sh log
  pico.sh shot
  pico.sh info
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
  adb -s "$serial" shell am start -n "$PACKAGE/.MainActivity" 2>/dev/null || \
    adb -s "$serial" shell am start -n "$PACKAGE/com.godotengine.godot.GodotApp" 2>/dev/null || \
    {
      echo "Ошибка: не удалось найти точку входа приложения" >&2
      return 1
    }
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

  # Журнал приложения: Android/data/<пакет>/files/logs
  local applog_remote="/sdcard/Android/data/$PACKAGE/files/logs"
  echo "Забираем журнал приложения из $applog_remote..."

  # Проверяем, есть ли файлы
  if adb -s "$serial" shell test -d "$applog_remote" 2>/dev/null; then
    adb -s "$serial" pull "$applog_remote" "$logdir/app-logs/" 2>/dev/null || true
    echo "Журнал приложения: $logdir/app-logs/"
  else
    echo "Директория $applog_remote не найдена или пуста"
  fi

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
  *)
    echo "Неизвестная команда: $1" >&2
    show_help
    exit 1
    ;;
esac
