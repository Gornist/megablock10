#!/usr/bin/env bash
# Сервер мира для П9 (очки): Серверная HARD двумя размерами, вход прямо в неё (без Архива и Ядра; те остаются в графе только как соседи по связям).
#   8  — tools/stand/p9_graph_hard8.json   (node_05 = server_room, 8×8: 2 Стража + Маяк + Датчик, 2 хранилища, shards 2, ice 2)
#   10 — tools/stand/p9_graph_hard10.json  (node_05 = server_room_hard10, 10×10: 3 Стража + Маяк + Датчик, 3 хранилища (третье — внутреннее), shards 3, ice 3)
# Остальное в графах и фальш-Мост (tools/stand/p9_bridge_fixture.json: Призрак на t03 -> node_05, RAM 14, демоны Извлечение 1-3 и Призрак — как на П8) одинаково.
# Размер: файл ~/pico-p9/size (одно слово 8|10) -> переменная P9_SIZE -> 8. p6_run.sh запускает сервер без окружения, поэтому размер для показа пишут в файл.
# Неверный размер — ошибка (код 2), сервер не стартует.
# Каждая строка вывода получает префикс `@<секунды.мс по часам devbox> `: в журнале сервера иначе нет времени, а p9_report.sh считает «время до хранилища».
# Токен терминала на очки: t03:token-t03. Порт 7777 (под `pico show`/`pico run … --port 7777`).
# Остановить: kill $(ss -ulpn | grep :7777 | sed -E "s/.*pid=([0-9]+).*/\1/")
# shellcheck disable=SC1090
. ~/netrun-env.sh 2>/dev/null || true
cd "$(dirname "$0")/.." || exit 1

size=""
if [ -r "$HOME/pico-p9/size" ]; then
  size=$(tr -d '[:space:]' < "$HOME/pico-p9/size")
fi
size=${size:-${P9_SIZE:-8}}
case "$size" in
  8) graph=p9_graph_hard8.json ;;
  10) graph=p9_graph_hard10.json ;;
  *) echo "srv_p9: размер «$size» — нужен 8 или 10 (файл ~/pico-p9/size или P9_SIZE)" >&2; exit 2 ;;
esac
echo "srv_p9: Серверная HARD ${size}x${size}, граф $graph"

stamp() {   # префикс времени; EPOCHREALTIME есть в bash >= 5, иначе date
  local line now frac
  while IFS= read -r line; do
    if [ -n "${EPOCHREALTIME:-}" ]; then now=${EPOCHREALTIME/,/.}; else now=$(date +%s.%N); fi
    frac=${now#*.}
    printf '@%s.%s %s\n' "${now%.*}" "${frac:0:3}" "$line"
  done
}

godot --headless --path . -- --graph="res://tools/stand/$graph" --bridge=fake --bridge-fixture="$PWD/tools/stand/p9_bridge_fixture.json" \
  --grace=3600 --vault-requires-open=true --exit-after=7200 > >(stamp) 2>&1 &
gpid=$!
trap 'kill "$gpid" 2>/dev/null' TERM INT EXIT
wait "$gpid"
