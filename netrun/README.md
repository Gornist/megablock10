# netrun — проект Godot (VR-клиент, сервер мира, плоская сборка)

Один проект Godot, три сборки (docs/netrun.md, «Сервер мира и клиент»). Рендерер — Mobile.

## Версии (закреплены на сезон)

- **Godot 4.7.2-stable** (из docs/netrun-vr-hardware.md). Шаблоны экспорта — той же версии; на машине разработки их может не быть,
  экспорт APK проверяет CI (задача G1).
- **gdUnit4 6.2.1** — лежит в `addons/gdUnit4` (источник: github.com/MikeSchulze/gdUnit4, тег v6.2.1). Проверен на Godot 4.7.2.
  Обновлять только осознанно, вместе с версией Godot.
- **OpenXR Vendors 5.1.0** — пока НЕ добавлен. Понадобится, если потребуется passthrough на Pico (П4) или вендорские
  расширения; требует Gradle-сборку и один вендор на шаблон экспорта. Для MVP на стандартном OpenXR не нужен.
- Очки — обычная Pico 4 (стандартный OpenXR).

## Структура

- `main.tscn`, `main.gd` — точка входа, выбирает режим.
- OpenXR включён только на Android (`openxr/enabled.android` в project.godot): плоская сборка и сервер его не поднимают. Риг — `client/xr_rig.tscn`, математика — `shared/rig_math.gd`. На ПК с рантаймом OpenXR: `-- --client --xr-mode on`.
- `shared/` — код, общий для сервера и клиента (в т.ч. `run_mode.gd` — выбор режима).
- `server/` — сервер мира. `client/` — клиент Pico 4 и плоская сборка. `tests/` — тесты gdUnit4.
- `export_presets.cfg` — пресеты: «Client Pico 4 (Android)» (OpenXR, arm64), «Server (dedicated)» (метка `dedicated_server`),
  «Flat debug (Linux)». Ключ подписи Android в репозиторий не кладём (в CI — ключ отладки).

## 3D-ассеты

`assets/models/<группа>/*.glb` — модели для Pico 4 (окружение, предметы; существа, аватар и дека — следующая часть). Каталог, соглашения
(оси, сетка 2x2 м, тиры, палитра, метки), числа треугольников и размеры — `assets/models/MANIFEST.md`; исходники — Blender-скрипты в
`assets/src/` (Blender запускается только на devbox, `assets/src/build_all.sh`); превью для приёмки — `assets/previews/`. Бюджет без
Blender: `python3 netrun/assets/src/check_budget.py`; импорт и метки проверяет `tests/assets_models_test.gd`. Файлы `.glb.import` лежат в
git (стабильные uid); после смены .glb — `godot --headless --path netrun --import`.

## Тесты

gdUnit4, как в CI (`.github/workflows/netrun.yml`): `netrun/tools/gdunit.sh [res://tests/файл_test.gd]` на devbox (весь набор — 223 теста,
несколько минут; долгое — через `devjob`). Код выхода: 0 — зелёно, 100 — упавшие, 101 — предупреждения (CI красит и их). Встроенный
`test_run` плагина Godot AI проект не видит — не использовать. Правки сцен и запуск игры — агент `godot-dev`.

## Как запускать

Режим: сервер, если `--headless` или метка `dedicated_server`/аргумент `--server`; клиент — на Android или `-- --client`;
иначе плоская сборка (`-- --flat`). Аргументы пользователя идут после `--`.

```sh
godot --headless --path netrun                         # сервер мира; выход по Ctrl+C / SIGTERM
godot --headless --path netrun -- --exit-after=5       # сервер, сам выйдет через 5 с
godot --path netrun -- --flat                          # плоская отладочная сборка (с окном)
godot --headless --path netrun --import                # импорт проекта (CI, первая загрузка)
```

Сеть (V2): сервер слушает ENet-порт 7777; токены пока из аргумента (вместо Моста, F1/M5), клиент берёт адрес и токен из аргументов.

```sh
godot --headless --path netrun -- --tokens=t1:alice,t2:bob --grace=20    # сервер: токен:сессия, окно возврата аватара, с
godot --path netrun -- --flat --host=127.0.0.1 --port=7777 --token=t1    # плоский клиент
```

Тест переподключения (сервер и клиент в одном процессе, `tests/net_reconnect_test.gd`): возврат в окно — тот же аватар
`node_07/avatar_<сессия>`, после окна — аватар убран, повторный вход — новый; плохой токен отклоняется. Окно в тесте 1,5 с;
значение по умолчанию 20 с (`NetConfig.DEFAULT_GRACE_SEC`) проверяется отдельно. Тихий обрыв сеть замечает за ~5 с (`NetServer.PEER_TIMEOUT_MS`).

## Мост (F1)

Сервер мира берёт токен терминала и операции с ценностями у Моста (`:netrun-bridge`, протокол — `docs/netrun-bridge-protocol.md`).
Выбор — аргументом `--bridge=`:

- `--bridge=fake` (по умолчанию) — `FakeBridge` в том же процессе, данные из `tests/fixtures/bridge_fixture.json`
  (другая фикстура — `--bridge-fixture=res://…`). Kotlin не нужен. Токены очков в фикстуре: `t03:token-t03` и `t04:token-t03`
  (сессия `s_fake000000000001` active, `…02` pending). Без `--bridge`, но с `--tokens=` работает старая заглушка (токен -> сессия).
- `--bridge=ws://хост:порт` — `BridgeClient` по WebSocket (`/netrun/v1` добавляется сам), ключ роли world — `--bridge-key=` или
  переменная `NETRUN_KEY_WORLD`.

Токен в `auth` очков — `терминал:токен` или JSON `{"terminal","token"}` (клиент: `--token=t03:token-t03`).

С настоящим Мостом локально (два терминала, из корня репозитория; Java 17+):

```sh
# 1. Мост (ключи ролей — в окружении; --test нужен только фейковому серверу мира в тестах Kotlin)
export NETRUN_KEY_WORLD=kw NETRUN_KEY_MASTER=km
./gradlew :netrun-bridge:run --args="--port 7410 --db /tmp/netrun-bridge.db"

# 2. Мастер заводит данные (put с ролью master по WebSocket, протокол раздел 5): узел node_07, терминал t03 с
#    token_sha256 = sha256 токена очков. Сессию создаёт только приём карточек телефона (M2) — пока её нет,
#    verify вернёт "" и очки получат отказ. Для проверки без телефона запустите Мост с --test и NETRUN_KEY_TEST
#    и сдайте деку op.submit_deck ролью test (см. netrun-bridge/src/test/…/FakeWorldRunTest.kt).

# 3. Сервер мира
godot --headless --path netrun -- --bridge=ws://127.0.0.1:7410 --bridge-key=kw
godot --path netrun -- --flat --host=127.0.0.1 --port=7777 --token=t03:<токен очков>
```

Если Мост не отвечает, сервер мира пробует снова раз в 2 с, а запрос токена получает отказ через 4 с (очки не пускаются).
Повтор операций после обрыва безопасен: `rid` детерминированные (`take:<сессия>:<предмет>`, `leave:…`, `finish:<сессия>`).
Тесты: `tests/fake_bridge_test.gd`, `tests/bridge_client_test.gd`; со стороны Моста — `FakeWorldRunTest` (фейковый сервер мира).

### Сервер мира одноразовый (M5)

Всё, что должно пережить рестарт, лежит в Мосте. `GrayNode` при старте ждёт связи, подписывается на `session/deck/node/item` и по
снимку: ставит активные сессии своего узла в окно возврата (`NetServer.expect_session`, `--grace=` секунд; вернулся клиент с тем же
токеном — тот же забег, нет — `run.finish` emergency/`disconnect`), возвращает шард держателю (`restore_holder`) или на постамент,
запоминает `lockdown_until`. Игрок возвращается в точку входа; перезарядки демонов и trace начинаются заново (в Мосте их нет).
Узел пишет `node.data.world = {up, players}`, связь игрока — `session.data.world` (`put_doc` с повтором при `version_conflict`).
`take` и `run.finish` при недоступном Мосте повторяются с тем же детерминированным `rid`. Дека берётся из `payload` предметов
`deck:<сессия>`, если там есть id демона (формат `ItemPayload` серверу мира пока неизвестен), иначе дека по умолчанию.
Тест без сети — `tests/restart_test.gd` (FakeBridge переживает «убитый» сервер).

Живой прогон с настоящим Мостом — `netrun/tools/live_run.sh` (на devbox, Gradle не на Mac): Мост (`--test --seed`, активная сессия,
дека и шард кладутся файлом), сервер мира, бот `--bot=ghost_run --bot-reconnect --bot-hold=10`; после взятия шарда сервер убивается
`kill -9` и поднимается снова, бот возвращается и выходит чисто, `tools/check_bridge.gd` проверяет документы (сессия closed/clean,
шард и дека у игрока в `outbox`, тревог аудитора нет). Итог — строка `LIVE_RUN PASS|FAIL: …`.

Экспорт (нужны шаблоны 4.7.2): `godot --headless --path netrun --export-debug "Client Pico 4 (Android)"`,
`--export-release "Server (dedicated)"`, `--export-debug "Flat debug (Linux)"`.

## Тесты (gdUnit4, без экрана)

Сначала один раз `godot --headless --path netrun --import`, затем:

```sh
godot --headless --path netrun -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests --ignoreHeadlessMode
```

Код возврата 0 — все тесты прошли. Отчёты — в `netrun/reports/` (в git не попадают).

## Выход (N6)

Удержание 3 с (VR — `menu_button`, настройка `XRRig.exit_button`; плоская сборка — Esc) → клиент шлёт серверу пакет
`{"t":"exit","reason":"manual_hold"}`; полоса прогресса — предмет мира перед глазами. Снятие очков (`NOTIFICATION_APPLICATION_PAUSED`,
сигналы OpenXR `session_stopping`/`focus_lost`) — та же отправка с причиной `headset_off`. Сервер (`NetServer.exit_event`) отдаёт
`{session, reason, under_hunt, deck_burned}`; флаг охоты ставит снаружи `set_under_hunt(session, bool)`. Обрыв связи выходом не
считается: по истечении окна возврата — событие `connection_lost`. Логика — `shared/exit_logic.gd`, тесты `exit_logic_test.gd`, `net_exit_test.gd`.

## Серый узел (N7)

`server/node/gray_node.gd` собирает узел node_07 (геометрия — `shared/node_layout.gd`: комната, укрытия, шард, площадка выхода,
2 ICE с патрулём): на сессию TraceMeter и DaemonSession (дека `ghost_1`, `jitter_1`), ICE шагает 10 раз/с и не видит игрока под
GHOST, сервер раз в 0.1 с шлёт снимок (`WorldMsg.STATE`: trace, ICE, перезарядки) и события (`WorldMsg.EVENT`). Шард берётся
через сервер (`grab`, не дальше 3.5 м), в Мосте это `op.take_from_node`; забег закрывает одна `run.finish`: чистый выход на
площадке (`leave`) — добыча на телефон, выброс ICE / флэтлайн / обрыв — добыча остаётся в узле.

Плоская сборка: 1–9 — применить демона из деки, X — выйти чисто на площадке, F / ЛКМ — взять шард; VR: левый X — применить
выбранного, Y — выбрать следующего. Бот — `tests/bot/bot_client.gd` (сценарии GHOST_RUN и EXPOSED_RUN), тест — `tests/gray_node_test.gd`.

## Граф узлов (W1)

`data/graph.json` — 12 узлов (BASE 6, HARD 4, NIGHTMARE 2), тоннели-связи (симметричные, до трёх на узел: i-я связь — слот
портала `NodeLayout.PORTAL_SLOTS[i]`), у каждого узла тир, число Soft ICE, число шардов; Black ICE — только в NIGHTMARE (по тиру,
в данных его нет). `entries` — узел входа по терминалу (`t01 → node_01`…), `default_entry` — для остальных; вход всегда не NIGHTMARE.
`settings` — все числа: `tunnel_sec`, `portal_dwell_sec`, `shard_refill_sec` по тирам, `refill_retry_sec`, `alert_*`, `lockdown_sec`.
Проверка данных — `NodeGraph.errors()` (симметрия, связность, слоты, тир входа); тест `node_graph_test.gd`.

Граф — режим по умолчанию: `godot --headless --path netrun` (или `-- --graph=<путь>`); прежний одиночный серый узел node_07 — `-- --single-node`.
Шарды сервер мира не создаёт: узел пополняется только из запаса, заложенного мастером (предметы `node:<узел>` в Мосте); пустой узел просто ждёт.
Битый граф в журнал (`push_error`) и сервер работает одним узлом.

- **Переход.** Игрок простоял `portal_dwell_sec` в радиусе портала → `GraphWorld.transit_check` (связь есть, узел не в локдауне,
  нет охоты Black ICE) → сессия уходит в «тоннель» (`NetServer.TUNNEL_NODE`: ни снимков, ни ICE, trace стоит, позиции клиента не
  принимаются), клиенту — событие `tunnel`; через `tunnel_sec` сессия приходит в новый узел у возвратного портала, клиенту — `node`
  (`arrive`). `DaemonSession` (trace, дека, перезарядки, GHOST) переходит тем же объектом; узлы ходят по общим часам `GraphClock`.
  Отказ — событие `portal_denied` (`lockdown | hunt | busy | not_linked`). Выход из забега в тоннеле закрывает забег в узле,
  откуда игрок ушёл.
- **Клиент.** `rig_test_scene.apply_node` рисует шарды и порталы узла по описанию сервера; `begin_tunnel`/`end_tunnel` — `TunnelFx`:
  тёмная сфера вокруг головы с тусклым потоком в шейдере, плавное затемнение; ход блокируется (`XRRig.movement_locked`), камера не
  двигается и не вращается; риг ставится на место входа под непрозрачной сферой. Шард в руке идёт с игроком из узла в узел.
  Вид тоннеля и читаемость порталов — только на очках (в тестах проверена логика).
- **Пополнение.** Шард, вынесенный на телефон или в другой узел, пустит слот (`NetServer.lock_object`, ответ клиенту `empty`) на
  `shard_refill_sec[тир]`; затем слот берёт свободный шард `node:<узел>` из Моста (сервер мира шардов не создаёт — их выпускает
  Мост), нет свободного — повтор через `refill_retry_sec`. Без Моста слот просто оживает. Добыча, оставшаяся в узле окончания
  (выброс, флэтлайн, обрыв), слот не пустит.
- **Остывание.** Тревога узла 0…1: растёт, когда trace игрока впервые достиг TRACE (`alert_per_trace`) и при выбросе
  (`alert_per_eject`); остывает за `alert_cool_sec`; при полной зрение и внимание ICE выше на `alert_boost`.
- **Локдаун.** После выброса Soft ICE: с Мостом — `node.lockdown_until` (ставит Мост по run.finish), без Моста — сервер мира на
  `lockdown_sec`. Закрытый узел не принимает через портал; портал в закрытый узел на карте серый.
- **Мост.** `session.data.world.node` — где игрок сейчас (после рестарта сервера мира узел находит игрока по нему).
  Ограничение действующего Моста (`ValueOps.activeSession`): `take_from_node` и `run.finish` требуют `node == session.node`,
  а в графе шард берут в узле, куда игрок прошёл тоннелем, — до правки Моста (принимать узел из `world.node` сессии) вне узла
  входа вынос шарда Мост отклонит; `FakeBridge` это допускает.
- **Бот.** `BotClient.Scenario.GRAPH_RUN` (`route`, `use_ghost`; из командной строки `--bot=graph_run --bot-route=node_02,node_03`):
  идёт порталами по маршруту, в последнем узле берёт шард и выходит чисто. Тест `graph_world_test.gd`: забег через три узла с
  возвращением добычи на телефон, trace и дека сохранены, пополнение, локдаун, тревога, 12 узлов по тирам.

## До 10 клиентов (P1)

- **Видимость по узлу:** у сессии есть узел (`NetServer.node_of`, по умолчанию `node_07`; `set_node`). `GrayNode` шлёт `state` и позиции
  аватаров только сессиям своего узла; у остальных пакеты просто не уходят.
- **Чужие аватары:** сообщение `av` (`WorldMsg.AVATARS`) — раз в 0.05 с, каждому игроку все остальные в его узле: `[[id, x, z], …]`
  и время сервера `k`. `state` (ICE, trace, дека) — раз в 0.1 с, тоже с `k`. Позицию свою клиент шлёт 20 раз/с.
- **Сглаживание на клиенте:** `StateBuffer` (снимки по времени сервера, интерполяция, пропущенный пакет, опоздавший пакет, скачок времени),
  `ServerClock` (смещение часов по самому быстрому пакету окна), `RemoteTracks` (всё вместе). Показ с задержкой: аватары 0.1 с, ICE 0.15 с
  (он приходит вдвое реже). Тесты — `tests/state_buffer_test.gd`.
- **Нагрузка:** `tests/multi_client_test.gd` — 10 ботов `BotClient.Scenario.LOITER` в одном узле; печатает `[P1-LOAD]`: трафик на клиента
  (полезная нагрузка, без заголовков ENet/UDP) и время шага сервера.

## e2e с телефоном (M6)

Сценарий `scripts/e2e/scenarios/netrun-run.sh` (общий стенд двух эмуляторов, `scripts/e2e/README.md`): Alice с эмулятора сдаёт Мосту
двух демонов (QR стойки подаётся debug-командой `DEBUG_SET netrun`), курок очков изображает роль `test` Моста (`session.confirm`:
настоящего курка у очков пока нет), бот `--bot=ghost_run --bot-daemon=<id предмета GHOST>` проходит узел по токену терминала. Затем
флэтлайн (`black_ice`) закрывается тестовым путём Моста: сервер мира без ICE и trace 100 исход сам не выдаёт. Мост запускается с
`--phone host:port=ключ` (только `--test`): эмулятор за NAT виден как 127.0.0.1, такой адрес Мост по строкам не запоминает.
