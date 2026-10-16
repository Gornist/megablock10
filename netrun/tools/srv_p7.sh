#!/usr/bin/env bash
# Сервер мира для П7 (очки): из этой копии netrun, граф tools/stand/p7_graph.json (такт; цепочка Архив node_03 BASE <-> Серверная node_05 HARD <-> Ядро node_11
# NIGHTMARE, в Ядре барьер закрыт, Black ICE «Гончая» спит; trace и тревога — из graph.json; «следующий стенд начинать с Архива» — П6-5), фальш-Мост с фикстурой
# tools/stand/p7_bridge_fixture.json (Призрак на t03 -> node_03, RAM 14, демоны Извлечение 1-3 и Призрак — как на П5/П6, шарды на узлах 03, 05 и 11).
# Токен терминала на очки: t03:token-t03 (вход — Архив). Порт 7777 (под `ctl.sh pico run Godot <мин> --port 7777`).
# Остановить: kill $(ss -ulpn | grep :7777 | sed -E "s/.*pid=([0-9]+).*/\1/")
# shellcheck disable=SC1090
. ~/netrun-env.sh 2>/dev/null || true
cd "$(dirname "$0")/.." || exit 1
exec godot --headless --path . -- --graph=res://tools/stand/p7_graph.json --bridge=fake --bridge-fixture="$PWD/tools/stand/p7_bridge_fixture.json" \
  --grace=3600 --vault-requires-open=true --exit-after=7200
