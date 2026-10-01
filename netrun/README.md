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
