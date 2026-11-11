# Карточка C: деки ЧАТ и ЗВОНКИ при настоящей связи — «ТЕЛЕФОН НЕ НА СВЯЗИ» и прокрутка фракционного чата

**Цель:** (1) когда телефон не на связи, ЧАТ и ЗВОНКИ деки честно говорят об этом; (2) фракционный чат листается: история в два экрана строк.
**Правила исполнителя:** `/private/tmp/claude-501/-Users-peachbite-Developer-megablock10/b5e593da-1b32-40c7-b757-4bc3f658fdd5/scratchpad/cards/rules-godot.md` — прочти первым.
**Worktree и ветка:** `/Users/peachbite/Developer/megablock10-wt/phone-ui`, ветка `agent/phone-ui` (от `agent/phone-link-remote`). Копия на devbox — `~/wt-phone-ui`.

## Зона записи (только это)
`netrun/shared/phone_link.gd`, `netrun/shared/phone_logic.gd`, `netrun/client/remote_phone_link.gd`, `netrun/client/ui/deck_chat.gd`, `netrun/client/ui/deck_calls.gd`, `netrun/client/ui/deck_panel.gd`,
`netrun/tests/deck_tabs_test.gd`, `netrun/tests/phone_logic_test.gd`, `netrun/tests/remote_phone_link_test.gd`, новый `netrun/tests/deck_phone_offline_test.gd` (если удобнее отдельным набором).
НЕ трогать: `proto_client.gd`, `world_ui.gd`, `fake_phone_link.gd`, любые звуки (`phone_sounds.gd` — другая задача).

## Досье
- Интерфейс связи: `netrun/shared/phone_link.gd` — есть `is_online() -> bool` (у фиктивной всегда true), сигналы `threads_changed`, `message_received`, `call_changed`. У настоящей связи `netrun/client/remote_phone_link.gd` свой сигнал `connection_changed(online: bool)` (его слушает `remote_phone_link_test.gd`).
- Дека: `netrun/client/ui/deck_panel.gd` (750 строк — читай только `set_phone` ~стр. 497 и места, где строятся вкладки ЧАТ/ЗВОНКИ), `deck_chat.gd` (326 строк: список диалогов, открытый диалог с пузырями и ряд заготовок `PhoneLogic.QUICK_REPLIES` ~стр. 62; `link.messages(_open_id, PhoneLogic.MESSAGES_SHOWN)` ~стр. 234), `deck_calls.gd` (230 строк).
- `PhoneLogic.MESSAGES_SHOWN := 8` — сколько последних сообщений показывает открытый диалог. Фракционный диалог у связи: поле `kind == PhoneLink.KIND_FACTION` (`"FACTION"`), его `id` — `"faction"`.
- Указатель нажимает кнопки (`MbButton`) лучом правой руки и курком; колёсика и перетаскивания в очках нет — прокрутка кнопками.
- Решение владельца 05.10.2026: «фракционный чат — два экрана скролла»; пока очки подключены к телефону, всё идёт от телефона; телефон может пропасть.

## Шаги (каждый — отдельный коммит, наборы тестов зелёные до коммита)
**Шаг 1 — общий сигнал о связи.** В `PhoneLink` (базовый) добавить `signal online_changed(online: bool)`; в `RemotePhoneLink` вместо `connection_changed` эмитить `online_changed` (старый сигнал удалить, его использования в `remote_phone_link_test.gd` заменить; поведение то же: true при принятом hello, false при обрыве).
Проверка: `dev.sh test remote_phone_link_test phone_link_test` → оба зелёные (сейчас 16 и 22 теста).

**Шаг 2 — «ТЕЛЕФОН НЕ НА СВЯЗИ».** Когда `link.is_online()` false: на вкладках ЧАТ и ЗВОНКИ сверху видна строка «ТЕЛЕФОН НЕ НА СВЯЗИ» (яркая, как предупреждение; стиль — `DeckTheme`/`DeckUi` как в соседнем коде), данные остаются последними известными, кнопки действий (заготовки, «ПРИНЯТЬ», «ПОЗВОНИТЬ» и т. п.) недоступны (`disabled`). Вернулась связь — строка исчезает, кнопки оживают. Обновление по сигналу `online_changed` (подписка в `set_phone`; у фиктивной связи сигнал не приходит и строки нет). Вкладки/бейджи счётчиков не ломать.
Тесты: в `deck_tabs_test.gd` или новом `deck_phone_offline_test.gd` — на фиктивной связи строки нет; на `RemotePhoneLink.new()` без сети (offline) строка есть и кнопка заготовки disabled; `link.online_changed.emit(true)` (или `on_frame` + имитация) убирает её. Для включения «онлайна» в тесте можно подменить связь тестовым потомком `PhoneLink` с переключаемым `is_online()`.

**Шаг 3 — прокрутка фракционного чата.** Для диалога с `kind == FACTION` в открытом виде: показывается страница из `PhoneLogic.MESSAGES_SHOWN` (8) сообщений, глубина истории — две страницы (16 сообщений, константа `PhoneLogic.FACTION_PAGES := 2`); кнопки «▲ СТАРШЕ» и «▼ НОВЕЕ» (в шапке или рядом с рядом заготовок; недоступные на границах — disabled); страница 0 = последние 8; смена диалога и новое входящее сообщение возвращают на страницу 0. Личные диалоги — как сейчас (8, без прокрутки).
Чистая логика — в `PhoneLogic` (статические функции без узлов, например `page_slice(messages: Array, page: int) -> Array` и `page_count(total: int) -> int`), тесты в `phone_logic_test.gd`; поведение в деке — тест в `deck_tabs_test.gd` (нажать «▲ СТАРШЕ» → видны сообщения 9–16 с конца; на крайней странице кнопка disabled; смена диалога сбрасывает страницу). Для истории в 16+ сообщений в тесте наполни фиктивную связь (`FakePhoneLink` умеет `receive_message(thread_id, from, text)`).

## Приёмка
- `dev.sh test remote_phone_link_test phone_link_test phone_logic_test deck_tabs_test deck_pointer_test deck_feedback_test` → все зелёные (до правок: 16, 22, 9, 32, 14, 10 тестов — кроме новых).
- `git diff --stat` от стартового коммита `2677ae8` — только файлы зоны.
- Отчёт по шаблону; в отчёте — как именно сделана строка и где стоят кнопки прокрутки.
