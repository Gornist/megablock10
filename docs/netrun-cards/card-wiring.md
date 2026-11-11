# Карточка B: подключить настоящую связь к клиенту очков

**Цель:** запуск клиента очков с `--phone=remote` (и из `netrun.cfg`) поднимает `RemotePhoneLink`, звуки и журнал; по умолчанию остаётся фиктивная связь.
**Правила исполнителя:** `/private/tmp/claude-501/-Users-peachbite-Developer-megablock10/b5e593da-1b32-40c7-b757-4bc3f658fdd5/scratchpad/cards/rules-godot.md` — прочти первым.
**Worktree и ветка:** `/Users/peachbite/Developer/megablock10-wt/phone-wire`, ветка `agent/phone-wire` (от `agent/phone-link-remote` ПОСЛЕ слияния звуков и интерфейса). Копия на devbox — `~/wt-phone-wire`.

## Зона записи (только это)
`netrun/client/proto_client.gd`, `netrun/tools/pico.sh`, `netrun/tests/phone_client_test.gd`, `netrun/README.md` (раздел «Дека на руке», только про связь с телефоном).
НЕ трогать: `remote_phone_link.gd`, `phone_sounds.gd`, деку и её вкладки, `docs/*` (документы правит оркестратор).

## Досье
- `netrun/client/proto_client.gd`: `const PHONE_FAKE/PHONE_OFF` ~стр. 28; `_setup_phone(args)` ~стр. 162 (создаёт `FakePhoneLink`, подписывает журнал `phone.msg`, `phone.call`, `phone.reply`, `deck.tab`); `static func phone_mode(args) -> Dictionary` ~стр. 145 (`{mode, warning}`, аргумент `--phone=fake|off`). Чтение `netrun.cfg` — как у `NetConfig.from_sources` (см. `netrun/shared/net_config.gd` или рядом; найди `grep -n "ConfigFile\|netrun.cfg" netrun/client/*.gd netrun/shared/*.gd`).
- Связь: `netrun/client/remote_phone_link.gd` — `start(port, token) -> Error`, `advance(delta)` зовёт `WorldUi` каждый кадр, сигналы `online_changed(online)` (после слияния карточки интерфейса), `message_received`, `sound_requested`, `phone_callsign`.
- Звуки: `netrun/client/phone_sounds.gd` — `PhoneSounds` (Node), `bind(link: RemotePhoneLink)`.
- Журнал клиента: `log_file.log("событие", {поля})`; токен в журнал не писать (как у `net.config`: `token=set`).
- Provision очков: `netrun/tools/pico.sh`, команда `provision --host=… --token=…` (пишет `netrun.cfg` на очки через adb); `provision --show` скрывает токен.
- Тесты режима: `netrun/tests/phone_client_test.gd` (там проверяется `phone_mode`).

## Что сделать (два коммита)

**Коммит 1 — клиент.**
1. `phone_mode(args, cfg)` понимает `--phone=remote`; новые аргументы `--phone-port=<порт>` (по умолчанию `RemotePhoneLink.DEFAULT_PORT`) и `--phone-token=<токен>`; те же значения читаются из `netrun.cfg` секции `[phone]` (`mode`, `port`, `token`), аргументы сильнее файла. Результат — словарь `{mode, port, token, warning}`. Неизвестный режим — как раньше: fake + предупреждение.
2. `_setup_phone`: для `remote` создать `RemotePhoneLink`, `start(port, token)`; ошибка слушания (порт занят) — запись `phone.warn` и откат на `FakePhoneLink` (честно: «связь с телефоном не поднялась, показываю фиктивную»); успех — `phone link=remote port=<порт>` в журнал (как строка `phone link=fake tabs=N`), добавить дочерним узлом `PhoneSounds` и `bind`. Журнал: `phone.online online=true|false callsign=…` по `online_changed`, `phone.sound kind=…` по `sound_requested`, `phone.msg`/`phone.call`/`phone.reply` — как у фиктивной.
3. Токен в журнал и в вывод не попадает ни в каком виде. Режим по умолчанию остаётся `fake`.
Тесты (`phone_client_test.gd`): разбор `phone_mode` — аргумент сильнее cfg; порт/токен по умолчанию; `remote` без токена допустим; мусор → fake + warning. Если проще — отдельный `phone_remote_client_test.gd` (в зону добавить).
Проверка: `dev.sh test phone_client_test remote_phone_link_test phone_sounds_test deck_tabs_test` → зелёные.

**Коммит 2 — provision.** `pico.sh provision` принимает `--phone=remote`, `--phone-port=`, `--phone-token=` и пишет секцию `[phone]` в `netrun.cfg` (не стирая секцию сети, которую пишет `--host/--token`); `provision --show` печатает секцию с токеном `***`; `--reset` как раньше удаляет файл. Это bash — на Mac `bash -n netrun/tools/pico.sh` и `shellcheck`-подобный просмотр глазами; на очки команду НЕ запускать (очки принадлежат владельцу; adb к очкам не трогай).

## Приёмка
- Тесты коммита 1 зелёные; `bash -n netrun/tools/pico.sh` → ок.
- `git diff --stat` — только файлы зоны. Отчёт по шаблону; в отчёте — примеры строк запуска (`--phone=remote --phone-port=7420 --phone-token=…`) и строка provision.
