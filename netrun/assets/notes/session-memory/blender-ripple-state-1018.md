---
name: blender-ripple-state-1018
description: "[Blender] 18.10: рябь облака — влиты #447 (dust_fps 0), #472 (заливка вдали), #473 (свет облака + dust_sharp + BackdropDome); ждём Godot (lights, купол), показ владельцу по его слову; замер preview_shimmer"
metadata:
  node_type: memory
  type: project
  originSessionId: 19addaff-6fd7-4efb-9767-ea646be6eae1
  modified: 2026-10-18T09:56:48.586Z
---

Продолжение [[blender-state-1016]]. Жалоба владельца 17–18.10 в очках: «частицы жутко рябят», «вдали рябит больше», «видна граница отрисовки», «лесенка жёстче на потолке/вдали»; руки — «заебись» (не трогать, глитч не трогать).

**Влито в main (main 73c7af1f на 18.10):** #447 `dust_fps` 10→0; #472 `dust_fill` (ячейка мельче 2 px экрана вдали → ровная заливка, lo 2 / hi 4); #473 `cloud_light.gdshaderinc` + `AssetMaterials.set_cloud_lights(tree, [{p,r,s,c}])` (≤12 источников, геттер `cloud_lights()`), дыхание только яркостью, `dust_sharp` 1, `BackdropDome` (assets/backdrop_dome.gd + shaders/backdrop.gdshader; render_priority −128, depth_test_disabled, из вида только поворот).

**Решения владельца 18.10:** принцип «частицы видны только в освещении, невидимые источники света»; идея фон-шар как меню Pico; порядок A (свет) → D (мягкий край) → B (купол) → C (потолок). Godot выбрала купол-меш вместо Sky (слой деки layers=behind).

**Ждёт Godot (карточки отправлены):** набор `lights` из раскладки + вызов `set_cloud_lights` в node_view (очередь после её разбиения gray_node.gd, #471+); подключить `BackdropDome.new()` и скрыть far_*/Horizon. Без этого вид на очках прежний. Показ владельцу — только по его «надеваю», Pipeline ставит бронь.

**Замер без очков:** `netrun/tools/dev.sh shot res://assets/preview_shimmer.tscn --pose=entry [--lights] [--dome] [--nofar] --tune=cloud_breath=0,…` (кадр 1504, MSAA 2×, сдвиг ≈0,2 px, разница соседних кадров по полосам верх/середина/низ; метрика сравнительная). Базовые: без дыхания всё 1,04→0,74 после #472; пол вблизи 0,74–0,99 (крупные жёсткие ячейки), dust_sharp 0,83; far_* дают ≈0,23 верхней полосы, с куполом и --nofar верх 0,42 (ручки rim_* на потолок не влияют).

**Шаг C вывод:** потолок solid_dark сам по себе спокоен (0,42), лесенка на очках — вероятно far_ceiling/far_floor; лечится куполом + скрытием far_* (вызов за Godot). cloud_ceiling=1 метрику ухудшил (верх 0,65→0,79) — не включать.

**Автопрогон на очках без человека:** `ctl.sh pico run Blender 25 --port 7777 -- bash ~/pico-bl-ripple/ripple_run.sh` (скрипт в scratchpad сессии, копия на devbox); ready требует света у очков (alg_confidence ≥ 1) — 18.10 ночью отказал «темно». Кадр глаза — PR Godot #455 (строка `[eye] diff=… luma=…`, нужен `perf=diag`); adb screencap показывает только компоновщик (кольца), не сцену. Скриншоты владельца: `adb pull /sdcard/Pictures/Screenshots/…` (source ~/netrun-env.sh на devbox).

**Грабли:** land.sh удаляет worktree влитых PR — перед работой проверять `ls`, иначе `cd` падает и команды идут в основной checkout (там не править); стек PR на непромёрженном: слить origin/agent/<ветка> в новую worktree.

**Решение владельца 18.10 (поздно): «убери плиты сверху и снизу вообще, оставим только горизонт».** Толкование: убрать потолок (ceiling*) и дальние пласты far_floor/far_ceiling; пол комнаты с сеткой остаётся; горизонт = BackdropDome. Код клиента (node_view MODULES, _far_transforms, подключение купола + set_alarm) — Godot; карточка ушла Pipeline на пересылку (Godot-сессии не было в ListAgents после перезапуска приложения). Мои следующие шаги: после PR Godot — кадр клиента (foyer_preview) + preview_shimmer, при необходимости подкрутить дымку купола; потом отдельным PR удалить glb потолка/far_* и тесты на них, когда владелец подтвердит. Godot #479 (свет облака: CloudLightPlan) CI зелёный, ждёт слияния; временная копия bl-eye479 / ветка agent/bl-eye479 и bl-ceiling — скажет владелец когда убирать.

**20.10 ночь (итог):** #533 (agent/bl-sky, последний коммит f7acb265) — непрозрачные грани облака (cloud_solid) + небо в просветах (sky_floor=CALM_BG + дымка + пылинки, haze 2,5) + карта освещённости (кадр 12,3→11,11 мс на Pico) + дешёвый купол + убраны «жирные линии»: OccupiedFloor (палитра cell_occupied_*), floor_grid=0, cloud_edge_gain 0,25, cloud_edge_mix 0, dust_fill=0. Стенд fc413527 собран (~/pico-bl-ripple), очки не проверены; Pipeline-сессии в ListAgents не было — сообщить «готово к слиянию #533 + стенд fc413527». Откаты [assets]: floor_grid=0.35, cloud_edge_gain=1.4, cloud_edge_mix=0.35, dust_fill=1, cloud_sky=0, cloud_solid=0, cloud_light=0, backdrop=0. Уроки: код выхода ci-wait ≠ результат (читать gh pr checks); перебор ручек на кадре клиента нашёл OccupiedFloor; sky в облаке — тест пылинок работает, прежний «белый» был моей ошибкой привязки; замер Pico автопрогоном (pico run, perf=on, нужен свет у очков).
