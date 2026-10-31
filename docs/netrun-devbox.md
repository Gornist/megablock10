# Godot и Сеть на devbox

**Статус:** актуально, сверено с main 30.10.2026. Документ про Godot-часть машины разработки: сервер мира, плоский клиент, очки Pico 4,
редактор Godot AI, стенды П6–П9, учения «выдернули питание». Саму машину (железо, установка, ssh, службы, очереди, брони, adb, очки без человека)
ведёт сессия Devbox — [devbox.md](devbox.md) (ТЗ), скрипты `scripts/devbox-bootstrap.sh`, `scripts/box.sh`; сюда это не дублируется.

Машина с 25.10.2026 переустановлена: Ubuntu 26.04.1, LAN `192.168.1.141` (`Host devbox` в `~/.ssh/config`), **без Tailscale и VPN**.
Прежняя инструкция под Ubuntu 24.04 (`scripts/devbox-setup.sh`) устарела — остался в репозитории как история; новая машина ставится
`scripts/devbox-bootstrap.sh` (порядок — в шапке скрипта и в `devbox.md`).

## Что на машине для Godot

| Что | Где | Откуда |
|---|---|---|
| Godot 4.7.2 | `~/.local/godot/godot-4.7.2-stable`, симлинк `~/.local/bin/godot` | `devbox-bootstrap.sh` (zip можно заранее положить в `~/bootstrap/dl/`) |
| Шаблоны экспорта 4.7.2 | `~/.local/share/godot/export_templates/4.7.2.stable/` (≈2 ГБ) | **bootstrap их не ставит**; доставляет сессия Godot |
| Окружение `. ~/netrun-env.sh` | `~/netrun-env.sh` (JDK 17, `ANDROID_HOME`, `PATH` с `~/.local/bin`, `platform-tools`, `emulator`) | **bootstrap не создаёт**; три строки, копия — `~/Developer/devbox-backup-1025/home/netrun-env.sh` на Mac |
| Рабочая копия редактора | worktree `~/wt-godot`, ветка `agent/godot` | `scripts/devbox-godot-ai.sh setup` |
| Сборки и конфиги для очков | `~/pico-cfg`, `~/pico-p6`, `~/pico-p7`, `~/pico-p9`; прогоны `~/box/runs/<время>-<владелец>` | скрипты `netrun/tools/` |
| Плагин Godot AI | `netrun/addons/godot_ai` в `~/wt-godot` (в git не кладётся) | `devbox-godot-ai.sh setup` |

Проверено по ssh 30.10: `godot`, `export_templates/4.7.2.stable`, `~/netrun-env.sh`, `~/wt-godot` (ветка `agent/godot`) и `editor_settings-4.7.tres` на месте.

**Шаблоны экспорта на чистой машине — класть с Mac.** С devbox GitHub и его CDN отдают 20–30 КБ/с (шаблоны ≈1,3 ГБ — около 17 часов), с Mac ≈10 МБ/с
(`devbox.md`, «Скорость с devbox»). Порядок: скачать на Mac `Godot_v4.7.2-stable_export_templates.tpz` из того же релиза `godot-builds`, что и сам Godot,
сверить контрольную сумму по файлу сумм релиза, распаковать (это zip с каталогом `templates/`) и `rsync` содержимого `templates/` в
`~/.local/share/godot/export_templates/4.7.2.stable/`; рядом должен лежать `version.txt`. Для Pico нужны `android_debug.apk`, `android_release.apk`,
`android_source.zip`; для Windows-сборки тестеров (`export_flat_win.sh`) — `windows_*` шаблоны.

## Запуск сервера Моста и мира (Godot)

На машине разработки (локально, без эмуляторов; `godot` в неинтерактивном ssh на PATH нет — сначала `. ~/netrun-env.sh`).

### 1. Сервер Моста (Kotlin + :kit)

```bash
cd ~/megablock10
./gradlew :netrun-bridge:test :netrun-bridge:detekt  # проверка (на практике — scripts/dbx.sh --auto, общий замок Gradle)
java -jar netrun-bridge/build/libs/*.jar             # запуск сервера (если собран)
```

### 2. Сервер мира (Godot headless)

```bash
cd ~/megablock10/netrun
godot --headless -- --tokens=t1:alice,t2:bob --exit-after=300
```

### 3. Плоская отладочная сборка (локально, с окном)

```bash
cd ~/megablock10/netrun
godot -- --flat --host=127.0.0.1 --port=7777 --token=t1
```

Управление — в шапке `client/flat_stub.gd` (T — прицел телепорта, ПКМ + мышь — осмотр, F / ЛКМ — взять, 1–9 — демон, X — выйти, Esc 3 с — экстренный выход);
ходьба WASD включается флагом `--walk`, режим поворота — `--turn=none|snap|smooth` (`client/proto_client.gd`). С аргументом `--tester` управление другое
(`client/solo_controls.gd`) — сборка для тестеров, см. [netrun-flat-windows.md](netrun-flat-windows.md). Аргументы игры при запуске из редактора
(`editor/run/main_run_args`) пишутся с ведущим `-- `, иначе Godot игре их не передаёт.

### 4. Очки Pico 4 по USB

Очки подключены к devbox кабелем; `adb` — после `. ~/netrun-env.sh`. Подключено ещё что-то (телефон, эмулятор) — `export ANDROID_SERIAL=<serial очков>`
(иначе `more than one device`). Известные ограничения очков (расширение айтрекинга, граница, режим рук, подпись, адрес и токен — файл `netrun.cfg`) —
`netrun/README.md`, «Pico 4».

- **Сборка для очков** — в своей копии проекта (не в `~/wt-godot`): `android/build` из `android_source.zip` шаблонов 4.7.2,
  `godot --headless --path <копия> --export-debug "Client Pico 4 (Android)"` (Gradle запускает сам экспорт, ~1,5 мин).
  Адрес сервера мира и токен — файлом на очках: `netrun/tools/pico.sh provision --host=<LAN-адрес devbox> --token=t1` (после каждого
  `adb uninstall` заново, `install -r` файл сохраняет); запасной способ для сборки на ПК — `-- --host=… --token=…` в `command_line/extra_args`.
- **Цикл:** `adb uninstall` (если подпись другая), `adb install -r <apk>` — **смотреть вывод**: при отказе на очках остаётся старая сборка;
  `adb logcat -c`, `tools/pico.sh launch`, `adb logcat -d | grep -E " godot +:|Fatal signal|F DEBUG"`; журнал игры — `tools/pico.sh log`
  (`user://logs` — внутренняя память приложения, читается через `run-as`). Подпись debug — `~/.android/debug.keystore`; после переустановки машины
  ключ возвращают из копии `devbox-backup-1025` (иначе «несовместимая подпись» и удаление приложения с очков).
- **Настройка комфорта без пересборки:** клиент читает необязательный `user://comfort.cfg` (секция `[comfort]`: `turn_mode`,
  `turn_speed_deg_s`, `turn_vignette`, `turn_ramp_up_s`, `turn_ramp_down_s`, `teleport_range`, `teleport_cooldown`, `teleport_blink_s`;
  пределы и значения по умолчанию — `netrun/client/comfort_config.gd`, `shared/rig_math.gd`). `tools/pico.sh tune` без аргументов показывает
  файл на очках; `tune turn_speed_deg_s=45 teleport_range=3.5` правит его (остальные ключи сохраняются), перезапускает приложение и печатает
  строку `comfort` из журнала; `tune --reset` удаляет файл. Файл пишется через `run-as` (отладочная сборка). Дальность и перезарядка
  телепорта ограничены пределами сервера (6 м, 0,6 с). Адрес сервера и токен через этот файл не передаются.
- **Без человека:** очки держит и будит `box.sh pico …` (см. следующие пункты и `devbox.md`, «Д5»); экран руками (`svc power stayon`, `KEYCODE_*`) не трогать.
  Если на очках не задана граница или спят контроллеры при включённом отслеживании рук, система открывает поверх приложения свой экран и ставит его
  на паузу — XR-проверку (трекинг, связь из VR) тогда делает только человек в очках.
- **Пресеты рендера и серии замеров** (рефактор Сети, G2): умолчания приняты и живут в коде (`RenderConfig`: msaa 2, foveation 0, layers behind;
  `AssetMaterials.KNOBS`: вид V10), поэтому `netrun.cfg` теперь нужен только для сравнений. `netrun/tools/pico_stand.sh <пресет> [ключ=значение ...]`
  пишет секции `[render]` и `[assets]` на очки (остальной файл не трогает; `--show`, `--reset`); пресеты: `base` (чистые умолчания), `bench`
  (`perf=on`, `bench=entry`), `cloud-props` (+ `cloud=1`; после B3 ≡ `bench`, оставлен алиасом), `cloud-vol`/`cloud-vol-budget`/`cloud-all`/`cloud-all-imp`
  (облако (Б), регулятор, импостор), `probe-sweep` (`cloud-props-2s` и ручка `cloud_two_sided` удалены 14.10: +5,5 мс, 66 fps). Ключи `RenderConfig.KEYS` идут
  в `[render]`, остальные — в `[assets]`. `netrun/tools/pico_series.sh "имя=пресет ключ=значение" ...` прогоняет варианты подряд (конфиг →
  перезапуск → итог `[bench]`/`[probe]` → PNG кадра при `perf=diag`) в `~/pico-series/<время>`; `PICO_SERVER_CMD` — команда сервера мира.
  Замеры и итоги серий — [netrun-bench.md](netrun-bench.md), [netrun-refactor-plan.md](netrun-refactor-plan.md).
  Грабли без человека: очки на столе засыпают по датчику (`dumpsys power` → `Asleep`; на Pico помогли
  `setprop pvr.factorytest.never.sleep 1` и `persist.pvr.sleep_by_static 0` — это системные настройки, только с владельцем, вернуть после серии); камеры в тёмной комнате дают системный диалог
  «Слишком темно» — `am start` отвечает «kept for the user», игра не стартует, серия честно прерывается; закрыть диалог должен человек.
- **Один путь к очкам (Д5, `docs/devbox.md` «Д5»; решение владельца 13.10 после 17:27):** серия, запись конфига и перезапуск игры идут только через
  `box.sh pico run|ready|start|fg` — в скриптах Сети нет своих wake/sleep/stayon/KEYCODE и нажатий в системных окнах. Запуск серии одной командой
  на devbox: `netrun/tools/pico_series.sh "имя=пресет ключ=значение" …` — сам зовёт `ctl.sh pico run Godot ${PICO_RUN_MIN:-20} [--port 7777]
  [--timeout $PICO_RUN_TIMEOUT] -- …`: бронь → разбудить → ready по ТРЕКИНГУ (свет, граница, контроллеры) → снимки и logcat прогона в
  `PICO_RUN_DIR` (туда же результаты серии) → погасить → снять бронь, вердикт последней строкой `pico run: …`. Коды run: команда rc | 20 не
  готово/вылезло окно («нужен человек» — строка в `~/box/attention.log`, дальше Pipeline) | 21 бронь чужая | 124 таймаут | 2 аргументы. Внутри
  серии между вариантами: идемпотентный `pico ready Godot` → `pico start Godot <пакет/активити>` («kept for the user» = НЕ ГОТОВО, строка
  `pico fg` в выводе) → итог `[bench]`; исходный `netrun.cfg` сохраняется на входе и возвращается в trap, игра останавливается. Без ~/box/repo
  (не devbox) — серия напрямую через `am start`, `PICO_READY_CMD` по желанию. Темно/нет трекинга = «physical»: ждёт света, повторять не нужно.
  `pico_stand.sh` перед записью конфига зовёт `check pico` (чужая бронь — отказ «кто и до когда»); `dev.sh shot` ставит запуск Godot в очередь
  `gpu` (`ctl.sh run gpu Godot --name shot`, ожидание `SHOT_QUEUE_WAIT`, 900 с), свой `flock /tmp/display.lock` остаётся внутри. Сервер стенда на
  свободном порту из пула 7800–7899: `scripts/box.sh up stand Godot -- <srv_p2.sh> {PORT}`. Подготовка очков на `pico.sh tune` — под бронью:
  `box.sh pico run Godot 5 -- netrun/tools/pico.sh tune …`.
  Самотест — `netrun/tools/box_guard_selftest.sh` (подложные ctl.sh и adb, `PICO_SERIAL=NOSUCH`, `BOX_TEST=1`; очков и `~/box` не касается; 21 проверка,
  прогон 30.10 — `OK`): проверки броней и серии гонять только им, а не рабочими скриптами по ssh — 13.10 17:27 так разбудили очки.
- **Стенды показа (П6, П7, П9).** Общее: скрипты стенда сначала проверяют, что в копии `netrun` есть кэш классов `.godot` (`netrun/tools/stand_guard.sh`: нет кэша — один раз импортирует проект, до 5 мин, не вышло — код 2; без кэша сервер падает «NetConfig/RunMode not declared»);
  показ человеку — только по слову владельца «надеваю», через `pico show` Devbox (бронь «Владелец», лобби допустимо, карточку границы не паркует и очки не гасит):
  `scripts/box.sh pico show Владелец --minutes <мин> -- bash netrun/tools/p6_run.sh` (install → provision → свежий сервер → start; «не готово» и «игра не встала» —
  не выход, сервер остаётся; конец — `box.sh pico unshow` после «снял» или `touch ~/pico-p6/stop`; журналы — в каталог показа: `server.log`, `logcat.txt`, `pico-log.txt`).
  Автопрогон без человека — `pico run Godot <мин> --port 7777 -- …` (тогда ready обязателен). Первый П6 16.10 сорвался на `pico run` под бронью человека: скрипт ждал
  бронь Godot и вышел на «не готово», сервер умер вместе с ним. Сервер и APK подменяются переменными `P6_SERVER` и `P6_APK`.
  - **П6** (16.10; Серверная HARD ↔ Ядро NIGHTMARE с Гончей, барьер закрыт, Black ICE спит): граф `netrun/tools/stand/p6_graph.json` (два узла,
    один тоннель; trace и тревога — из `data/graph.json`), фальш-Мост `p6_bridge_fixture.json` (Призрак на t03, RAM 14, демоны Извлечение 1–3 и Призрак,
    шарды на узлах 05 и 11), сервер `tools/srv_p6.sh` (порт 7777). APK — `scripts/box.sh run gpu Godot --name p6-build -- bash netrun/tools/p6_build.sh`
    → `~/pico-p6/netrun-client-p6.apk` (отдельно от `~/pico-cfg`).
  - **П7** (16.10, «следующий стенд начинать с Архива», П6-5): цепочка Архив node_03 (BASE, `server_room_light`) ↔ Серверная node_05 ↔ Ядро node_11,
    вход t03 в Архив, остальное как П6: `tools/stand/p7_graph.json`, `p7_bridge_fixture.json`, `tools/srv_p7.sh`; APK — `P6_DIR=$HOME/pico-p7 scripts/box.sh run gpu Godot --name p7-build
    -- bash netrun/tools/p6_build.sh` → `~/pico-p7/netrun-client-p6.apk`; показ — `P6_SERVER=srv_p7.sh P6_APK=$HOME/pico-p7/netrun-client-p6.apk scripts/box.sh pico show Владелец
    --minutes <мин> -- bash netrun/tools/p6_run.sh`.
  - **П9** (Серверная HARD двумя размерами, вход прямо в неё): `tools/stand/p9_graph_hard8.json` (8×8) и `p9_graph_hard10.json` (10×10), фальш-Мост `p9_bridge_fixture.json`,
    сервер `tools/srv_p9.sh` (размер — файл `~/pico-p9/size` со словом `8` или `10`, либо `P9_SIZE`; в журнал каждая строка идёт с меткой времени). Отчёт по прогону —
    `netrun/tools/p9_report.sh <каталог прогона | server.log>` (время до хранилища, прыжки, поимки, тревога, взломы). Показ — как у П7 с `P6_SERVER=srv_p9.sh` и APK из `~/pico-p9`.
- **Падение в нативном коде:** кадры `libgodot_android.so` в tombstone без имён (библиотека шаблона уже без символов). Функцию находит
  дизассемблер по адресу кадра: `$ANDROID_HOME/ndk/<версия>/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objdump -d --start-address=…`
  по `<копия>/android/build/build/intermediates/merged_native_libs/…/arm64-v8a/libgodot_android.so` (BuildId в tombstone должен совпасть).
  Символы Godot публикует только для template_release и редактора.

## Godot AI: агент `godot-dev` и тесты Godot-части

Живой редактор Godot с плагином [Godot AI](https://github.com/hi-godot/godot-ai) (MCP, v4.2.3) на devbox, на реальном дисплее (GNOME, GTX 1650).
Через него агент `godot-dev` (`.claude/agents/godot-dev.md`) правит сцены и ноды, запускает игру, снимает кадры и читает журналы.

- **Рабочая копия:** git worktree `~/wt-godot`, ветка `agent/godot`. Принести на Mac: `git fetch devbox agent/godot`. Скрипт `devbox-godot-ai.sh` по умолчанию
  режет её от `main` (`GODOT_AI_BASE`, #562; прежняя база `agent/netrun` удалена).
- **Редактор:** `scripts/devbox-godot-ai.sh setup` (один раз: worktree, плагин с проверкой sha256, импорт), затем `start|stop|status`;
  `autostart` — поднимать при входе nick (после переустановки 25.10 в `~/.config/autostart` лежит только `devbox-session.desktop`, `godot-ai.desktop` вернёт `autostart`).
  Плагин в репозиторий не кладём (`netrun/.gitignore`): `start` дописывает в `project.godot`
  плагин, автозагрузку `_mcp_game_helper` и `run/main_run_args`, `stop` снимает; от забытого `stop` страхует хук `pre-commit`
  (ставит `setup`, или `scripts/devbox-godot-ai.sh hook`): в коммит уходит `project.godot` без этих строк, рабочий файл он не трогает.
  Файл в репозитории приведён к формату, который пишет редактор Godot 4.7, поэтому открытие проекта дерево не пачкает; если
  `git status` показывает `netrun/project.godot` — настройки действительно меняли (или редактор сейчас открыт с плагином).
- **Автозапуск сеанса** (графический вход nick, служба `box-adb`, Blender, ожидание редактора Godot на порту 8000, самопроверка, `~/box/boot.report`) — зона Devbox,
  описан в [devbox.md](devbox.md), «Что уже работает». Для Godot важно одно: автозапуск лишь ждёт порт 8000 до 90 с и пишет проблему в отчёт, если редактор не поднялся.
- **Godot не должен убивать общий adb.** При выходе Godot (в том числе `--headless --import` из `gdunit.sh`, `dev.sh`, `live_run.sh`…) вызывает `adb kill-server`
  (настройка редактора `export/android/shutdown_adb_on_exit`, по умолчанию true) — 13.10 это пять раз оборвало Pico и телефоны всем сессиям.
  Защита: в `~/.config/godot/editor_settings-4.7.tres` стоит `export/android/shutdown_adb_on_exit = false` (проверено по ssh 30.10 — на месте и после переустановки;
  при смене версии Godot файл называется иначе — строку добавить снова; поставила сессия Devbox). Счётчик убийств — в `scripts/box.sh status`. **Переменную `ANDROID_ADB_SERVER_PORT=5099` в скриптах
  не ставить** (было в `netrun/tools/*.sh` до 14.10): редактор сам зовёт `adb` (список устройств для запуска), с этой переменной это поднимает второй
  adb-сервер на 5099, он забирает USB очков, и основной на 5037 их не видит (Devbox, 14.10: очки пропали из adb после перезагрузки; лечение — `box.sh adb-rescue`).
  Проверка: `ps -eo cmd | grep "adb.*server"` показывает только `:5037 server nodaemon`. Исключение — `gdunit_ci.sh` (раннер CI без устройств).
- **Клиент (Claude Code на Mac):** `.mcp.json` запускает `ssh devbox … uvx godot-ai==4.2.3 attach` (stdio-мост) — туннеля и токенов нет. Телеметрию
  плагина отключает `--disable-telemetry` / `GODOT_AI_DISABLE_TELEMETRY=1`.
- **Тесты — gdUnit4, как в CI:** `ssh devbox 'cd ~/wt-godot && netrun/tools/gdunit.sh [res://tests/файл_test.gd]'` (весь набор — 171 файл `netrun/tests/*_test.gd`,
  ≈1900 `func test_` на 30.10; зелёный при открытом редакторе; долго — через `devjob start`; в цикле правки — `netrun/tools/dev.sh test`, skill `netrun-loop`).
  Встроенный `test_run` плагина не используем: он не знает gdUnit4.
- **Что не покрыто:** снимки кадра идут из плоской сборки, VR (OpenXR, трекинг, кадр на Pico 4) на devbox не проверить без человека в очках.
- **Ловушки:** не искать редактор через `pkill -f`/`ps | grep` по строке из самой ssh-команды (убьёте сессию); после остановки ждать
  освобождения портов 8000/9500, lock в `~/.config/godot-ai/capabilities` не удалять — иначе «server start blocked».

## Стенд e2e на devbox (E1)

Сам стенд — `scripts/e2e/README.md`. Две причины прежних красных сценариев были в стенде, не в приложении (чинится в коде, помнить «почему»):

- **Локаль POSIX** (ssh без `LANG`): `grep -i` в `screen_has` не сворачивает регистр кириллицы, заголовки рисуются заглавными. `scripts/e2e/lib.sh` сам выставляет UTF-8-локаль (`LC_ALL`).
- **Виртуальный Wi-Fi без интернета**: Android отключал сохранённую сеть `AndroidWifi` (`NETWORK_SELECTION_DISABLED_NO_INTERNET_PERMANENT`). `scripts/e2e/up.sh` выключает проверку (`settings put global captive_portal_mode 0`).

## Учения: выдернули питание

Проверка, что внезапное отключение питания площадки (мини-ПК с Мостом и сервером мира) ничего не теряет. Скрипт `netrun/tools/power_cut.sh` поднимает Мост (SQLite в WAL) и сервер мира, запускает ботов, ждёт, пока хотя бы две сессии откроются посреди забега, и убивает **всё разом** `kill -9` (Мост тоже), затем поднимает заново на той же базе и сверяет слепки до и после:

- число и набор id предметов те же, что в начальных данных (не пропал и не раздвоился), аудитор Моста без тревог;
- документы узлов на месте, версии не откатились, локдаун и цель мастера (`node_cfg.goal`) не изменились;
- открытых сессий нет: недоигранные закрыты сервером мира по окну возврата, остальные доиграны ботами второй волны.

Запуск на devbox (после `. ~/netrun-env.sh`): `timeout 900 netrun/tools/power_cut.sh`; на занятой машине — `BRIDGE_PORT=7610 LINE_PORT=7611 ENET_PORT=7977 …` (умолчания 7410, 7411, 7777). Параметры `--bots=4`, `--seed=<число>`, `--dir=<каталог журналов>`. Итог — одна строка `POWER_CUT PASS|FAIL: …`, журналы и слепки (`before.json`, `after.json`) — в каталоге из последней строки. Что переживает рестарт сервера мира, лежит в документах Моста: локдаун и цели — `node`/`node_cfg`, шарды — предметы с владельцем `node:<узел>`, тревога и сроки пополнения слотов — `node.data.world` (`alert`, `alert_at`, `refill`).

### На машине площадки

1. Установить юниты из `netrun/tools/systemd/` (`netrun-bridge.service`, `netrun-world.service`, `netrun.target`) в `/etc/systemd/system/`, поправить пути и пользователя, положить ключи ролей в `/etc/netrun/keys.env` (права 600), `systemctl daemon-reload && systemctl enable --now netrun.target`.
2. Убедиться, что оба юнита активны: `systemctl is-active netrun-bridge netrun-world`.
3. Начать забеги (боты `soak.sh` или очки), затем выдернуть шнур питания (или `sudo systemctl kill -s KILL netrun-world netrun-bridge` для проверки без шнура: `Restart=always` поднимет оба за несколько секунд).
4. После загрузки: `systemctl is-active …` снова `active`, аудитор Моста без тревог, на дашборде число предметов то же, активные забеги продолжаются или закрыты как `emergency`.
