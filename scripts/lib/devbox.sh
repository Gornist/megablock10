# Общая обвязка ssh к devbox и к хосту Сети. Подключается через `. "$ROOT/scripts/lib/devbox.sh"` (сама ничего не запускает).
#   dssh <команда…>   — выполнить на машине DEVBOX_HOST; stdin сохраняется. На самой машине (из клона ~/box/repo, из ssh-сеанса сессии)
#                       идёт локально: ssh к себе там не выходит («Host key verification failed», 13.10).
#   unreachable       — ssh не прошёл (код 255): печатает вердикт «машина выключена или не в сети»; машины ходят только по LAN.
#   onbox             — то же, что dssh на самой машине (bash -c "$*").
#   gpu_guard_sh      — печатает кусок shell для УДАЛЁННОГО скрипта кадров: функции vram_check (перед запуском) и vram_why (кадров нет).
# Настройка до вызова: DEVBOX_TMO — ConnectTimeout, с (по умолчанию 10; dbx.sh берёт 15, box.sh 8), DEVBOX_HOST (devbox),
# DEVBOX_LAN_IP (по имени хоста: devbox — 192.168.1.141, хост Сети — NETRUN_LAN_IP; Tailscale и VPN на devbox убраны 25.10.2026,
# 100.80.115.46 больше не существует).
#
# Хост Сети (Godot, Blender, сборка APK, очки Pico) с 14.11.2026 — отдельная машина: NETRUN_HOST (по умолчанию 3060pc, рабочий ПК
# владельца, LAN NETRUN_LAN_IP=192.168.1.53; docs/devbox.md, «Хост Сети»). Алиас devbox на неё НЕ перенаправлять: туда ходят Gradle и e2e,
# для которых на 3060pc ничего нет. Скрипты Сети задают DEVBOX_HOST=$NETRUN_HOST до подключения этого файла.
NETRUN_HOST=${NETRUN_HOST:-3060pc}
NETRUN_LAN_IP=${NETRUN_LAN_IP:-192.168.1.53}
DEVBOX_HOST=${DEVBOX_HOST:-devbox}
if [ -z "${DEVBOX_LAN_IP:-}" ]; then
  case ${DEVBOX_HOST#*@} in
    devbox) DEVBOX_LAN_IP=192.168.1.141 ;;
    "$NETRUN_HOST") DEVBOX_LAN_IP=$NETRUN_LAN_IP ;;
    *) DEVBOX_LAN_IP=$(ssh -G "$DEVBOX_HOST" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }') ;;
  esac
fi

onbox() { bash -c "$*"; }

# Запуск на самой машине: короткое имя совпадает с именем хоста (без user@); у 3060pc hostname -s = 3060pc, на нём dssh (dev.sh) идёт локально.
on_target() { [ "$(hostname -s 2>/dev/null)" = "${DEVBOX_HOST#*@}" ]; }

dssh() {
  if on_target; then
    onbox "$@"
  else
    ssh -o ConnectTimeout="${DEVBOX_TMO:-10}" -o BatchMode=yes "$DEVBOX_HOST" "$@"
  fi
}

# Видеопамять хоста Сети занята локальной LLM (на 3060pc 10,8 из 12 ГБ держит сервис моделей skill offrail): кадр Godot без памяти
# падает или молча не пишет файлов. vram_check отказывает с вердиктом, если свободно меньше NETRUN_GPU_MIN_MIB (по умолчанию 1024),
# vram_why после пустого прогона называет причину. Модель НЕ выгружаем: только владелец решает, когда её остановить.
# Без nvidia-smi (другая видеокарта) обе молчат. Код отказа vram_check — 4.
gpu_guard_sh() {
  cat <<GUARD_EOF
vram_report() {
  echo "  видеопамять: свободно \$1 из \$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1) МиБ; держат:"
  nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null | sed 's/^/    /'
  echo "  ! чаще всего это локальная LLM владельца (skill offrail): без его слова не выгружать — спросить, можно ли остановить модель"
}
vram_free() { nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1; }
vram_check() {
  local free need=\${NETRUN_GPU_MIN_MIB:-${NETRUN_GPU_MIN_MIB:-1024}}
  free=\$(vram_free); [ -n "\$free" ] || return 0
  [ "\$free" -ge "\$need" ] && return 0
  echo "ВИДЕОПАМЯТЬ: свободно \$free МиБ < нужных \$need — кадр не снимаю (порог: NETRUN_GPU_MIN_MIB)"; vram_report "\$free"; return 4
}
vram_why() {  # \$1 — журнал прогона
  local free; free=\$(vram_free); [ -n "\$free" ] || return 0
  if grep -aqiE 'OUT_OF_(DEVICE|HOST)_MEMORY|out of memory|vkAllocateMemory|Unable to allocate' "\$1" 2>/dev/null || [ "\$free" -lt 1024 ]; then
    echo "ВИДЕОПАМЯТЬ: похоже, кадру не хватило памяти GPU (журнал \$1)"; vram_report "\$free"
  fi
}
GUARD_EOF
}

unreachable() {
  local lan=нет
  ping -c1 -t2 "$DEVBOX_LAN_IP" >/dev/null 2>&1 && lan=есть
  echo "$DEVBOX_HOST: НЕДОСТУПЕН — ssh не отвечает (ping LAN ${DEVBOX_LAN_IP:-?}: $lan)"
  if [ "$lan" = есть ]; then
    echo "  ! машина отвечает на ping, но ssh нет: служба ssh или ключ (ssh -v $DEVBOX_HOST); после переустановки — ssh-keygen -R $DEVBOX_LAN_IP"
  else
    echo "  ! машина выключена или не в сети (кабель, питание, роутер) — владельцу"
  fi
}
