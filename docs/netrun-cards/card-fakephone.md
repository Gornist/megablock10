# Карточка D: «фальшивый телефон» — инструмент живой проверки и контрактные кадры

**Цель:** проверять связь очков с телефоном без приложения Android: скрипт на devbox подключается к очкам как телефон и шлёт кадры по сценарию, печатая, что приходит в ответ; те же кадры — файл-контракт для тестов обеих сторон.
**Правила исполнителя:** `/private/tmp/claude-501/-Users-peachbite-Developer-megablock10/b5e593da-1b32-40c7-b757-4bc3f658fdd5/scratchpad/cards/rules-godot.md` — прочти первым.
**Worktree и ветка:** `/Users/peachbite/Developer/megablock10-wt/phone-fake`, ветка `agent/phone-fake` (от `agent/phone-link-remote`). Копия на devbox — `~/wt-phone-fake`.

## Зона записи (только это)
`netrun/tools/fake_phone.gd` (новый, `extends SceneTree`), `netrun/tools/fake_phone.sh` (новый), `netrun/tests/fixtures/phone_frames.json` (новый), `netrun/tests/fake_phone_test.gd` (новый).
НЕ трогать: `remote_phone_link.gd`, `proto_client.gd`, деку, звуки, `pico.sh`.

## Досье
- Формат кадров — `docs/netrun-phone-link.md`, раздел 2, подразделы «Конверт кадра (точный формат)» и «Уточнения формата» (читай только их). Приёмник — `netrun/client/remote_phone_link.gd`: `func on_frame(frame: Dictionary)` разбирает кадры телефона, `advance(delta)` крутит сокеты, `start(port, token)`.
- Порт по умолчанию 7420, токен в query адреса: `ws://хост:порт/?token=<токен>`; первый кадр телефона — `hello{v:1,callsign}`; очки отвечают `hello_ack{v}` и `resync`.
- Живой тест соединения в том же процессе уже есть: `netrun/tests/remote_phone_link_test.gd` (`_connect`, `_pump`, `_say` — смотри как образец, не копируй целиком).
- Запуск Godot на devbox: `. ~/netrun-env.sh; godot --headless --path netrun -s res://tools/fake_phone.gd -- <аргументы>` (путь `godot` задаёт `~/netrun-env.sh`; на Mac Godot не запускать).
- Python-библиотек WebSocket на devbox нет — поэтому инструмент на GDScript.

## Что сделать (два коммита)

**Коммит 1 — контрактный файл кадров.** `netrun/tests/fixtures/phone_frames.json`: объект `{"phone_to_glasses": {имя: кадр, …}, "glasses_to_phone": {имя: кадр, …}}` с по одному каноническому примеру КАЖДОГО типа кадра из документа (телефон→очки: hello, threads (ЛС ЛИС с unread 2 и FACTION «faction» ВОЛЬНЫЕ), messages (по каждому диалогу), message (новое входящее и смена статуса), call (по одному на каждую фазу idle/outgoing/incoming/in_call), call_log, contacts, sound (все четыре kind); очки→телефон: hello_ack, send_text (с preset), mark_read, accept, decline, hangup, mute, start_call, resync). Данные осмысленные (позывные ЛИС, ВОБЛА, ШЕРШЕНЬ; тексты по-русски; ключ ЛС — строка вида `MFkwEwYH…` вымышленная).
Тест `fake_phone_test.gd` (первая часть): все кадры `phone_to_glasses` принимаются `RemotePhoneLink.on_frame` без ошибок и дают ожидаемый эффект (количество диалогов, сообщения, фаза звонка, сигнал `sound_requested`); все кадры `glasses_to_phone` — валидный JSON с полем `t` из набора типов документа, а команда `send_text` содержит `preset` из `PhoneLogic.QUICK_REPLY_IDS`. Ожидаемый вердикт: `dev.sh test fake_phone_test remote_phone_link_test` → зелёные.

**Коммит 2 — скрипт.** `netrun/tools/fake_phone.gd`: аргументы после `--`: `--url=ws://хост:порт/?token=…` (обяз.), `--scenario=idle|chat|call|all` (по умолчанию `all`), `--callsign=Призрак`. Поведение: подключиться, послать `hello`, дождаться `hello_ack`; на `resync` отдать `threads`, `messages` по каждому диалогу, `call_log`, `contacts` (кадры берёт из `phone_frames.json`: путь `res://tests/fixtures/phone_frames.json`); сценарии по таймеру (счёт на `_process`, без sleep): `chat` — через 3 с новое входящее ЛИС + `sound{message}`, через 8 с ещё одно во фракцию; `call` — через 3 с `call incoming` + `sound{ring}`, через 12 с `call idle` + `sound{stop}`; `all` — оба по очереди. Все кадры от очков печатаются в stdout одной строкой `<- {json}`, отправленные — `-> {json}`. На `send_text` отвечает как телефон: `message` с `mine:true`, текстом из таблицы `PhoneLogic.QUICK_REPLIES`/`QUICK_REPLY_IDS` и `status:"sent"`, через секунду `status:"delivered"`; на `mark_read` — `threads` с `unread:0` для того диалога; на `accept` — `call in_call`; `decline`/`hangup` — `call idle` + `sound{stop}`; `mute` — `call` с `muted`; `start_call` — `call outgoing` + `sound{ringback}`, через 5 с `in_call`. Обрыв связи — код выхода 3 и строка `closed code=… reason=…`; успешный сценарий до конца — выход 0 после паузы 30 с на ответы (не `sleep`: счёт кадров).
`netrun/tools/fake_phone.sh <хост_очков> [токен] [сценарий]`: на Mac и на devbox одинаково — если запущен не на devbox, сам идёт `ssh devbox` и запускает там `godot --headless … fake_phone.gd` из каталога `~/wt-<ветка>` (как `dev.sh`: сначала `netrun/tools/dev.sh sync`, потом команда); печатает вердикт в конце: `FAKE_PHONE ok | closed code=…`.
Тест (вторая часть `fake_phone_test.gd`): поднять `RemotePhoneLink` на свободном порту, запустить логику скрипта как класс в том же процессе нельзя — поэтому вынеси разбор и ответы телефона в статические функции `FakePhone.reply_to(frame: Dictionary, frames: Dictionary) -> Array` (в `fake_phone.gd` или соседнем `fake_phone_logic.gd` в `netrun/tools/`) и проверь их без сети: `send_text`→`message`(mine) с верным текстом, `accept`→`call in_call`, `hangup`→`call idle`+`sound stop`, `mark_read`→`threads` с `unread:0`.

## Приёмка
- `dev.sh test fake_phone_test remote_phone_link_test` → зелёные.
- Живая сверка один раз: на devbox запустить `RemotePhoneLink` и скрипт друг против друга НЕ нужно (очки в это время заняты); достаточно тестов.
- `git diff --stat` — только файлы зоны. Отчёт по шаблону; в отчёте — пример строки запуска.
