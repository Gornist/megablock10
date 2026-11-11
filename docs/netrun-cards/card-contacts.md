# Карточка H: контакты телефона на вкладке ЗВОНКИ

**Цель:** на вкладке ЗВОНКИ деки виден список контактов телефона (кадр `contacts` уже приходит и хранится в `RemotePhoneLink.contacts()`), у каждого кнопка «ПОЗВОНИТЬ»; на свежем телефоне без журнала звонков позвонить можно.
**Правила исполнителя:** `/private/tmp/claude-501/-Users-peachbite-Developer-megablock10/b5e593da-1b32-40c7-b757-4bc3f658fdd5/scratchpad/cards/rules-godot.md` — прочти первым.
**Worktree и ветка:** `/Users/peachbite/Developer/megablock10-wt/phone-contacts`, ветка `agent/phone-contacts` (от `main`). Копия на devbox — `~/wt-phone-contacts`.

## Зона записи (только это)
`netrun/shared/phone_link.gd`, `netrun/client/remote_phone_link.gd`, `netrun/client/ui/deck_calls.gd`, `netrun/client/ui/deck_panel.gd`, `netrun/tests/deck_tabs_test.gd`, `netrun/tests/deck_phone_offline_test.gd`, `netrun/tests/remote_phone_link_test.gd`, новый `netrun/tests/deck_contacts_test.gd` (+ `.gd.uid`, взять scp с devbox).
НЕ трогать: голос (`phone_voice*.gd`), `proto_client.gd`, `fake_phone_link.gd` (у фиктивной связи `contacts()` уже отдаёт список), документы. Очки/adb не трогать (очки на владельце).

## Досье
- `netrun/shared/phone_link.gd:96` — `func contacts() -> Array` (элементы `{key, title}`); сигналы связи там же (`threads_changed`, `message_received`, `call_changed`, `online_changed`).
- `netrun/client/remote_phone_link.gd` ~стр. 274: ветка `"contacts"` в `on_frame` заполняет `_contacts`, но сигнала нет.
- `netrun/client/ui/deck_calls.gd` (≈260 строк): карточка звонка, журнал (`_refresh_log` ~стр. 201, `_log_row` ~стр. 218 с кнопкой «ПОЗВОНИТЬ» → `link.start_call(peer)` и сигналом `log_call_requested`), `apply_online()` блокирует кнопки при офлайне, `refresh()`.
- Приложению `start_call{peer}` нужен ПОЗЫВНОЙ собеседника — берём `title` контакта.

## Что сделать (два коммита, тесты зелёные до каждого)
**Коммит 1 — сигнал.** В `PhoneLink` добавить `signal contacts_changed`; `RemotePhoneLink` испускает его после разбора кадра `contacts`. Тест в `remote_phone_link_test.gd`: кадр `contacts` из `phone_frames.json` (ключ `contacts` в `phone_to_glasses`) заполняет `contacts()` и испускает сигнал один раз.
**Коммит 2 — интерфейс.** В `deck_calls.gd` над журналом блок «КОНТАКТЫ» (заголовок в стиле соседнего кода), по строке на контакт: имя (`title`) и кнопка «ПОЗВОНИТЬ» (`link.start_call(title)` и тот же сигнал `log_call_requested`); кнопки недоступны при занятом звонке (как в журнале) и при офлайне (`apply_online`); блока нет, если контактов нет; не больше 8 контактов (остальные скрыть; константа вверху файла); обновление по `contacts_changed` (подписка в `bind`, повторный `bind` отписывает прежнюю, как у других сигналов в файле). Не ломать `button_texts()`, `find_button()`, прокрутку и счётчики вкладок. Тесты в новом `deck_contacts_test.gd`: нет контактов — блока нет; три контакта — три строки с кнопками, позвонить → `start_call` с позывным; идёт звонок — кнопки disabled; связь офлайн — disabled; сигнал `contacts_changed` перестраивает блок; больше 8 — показано 8.
Проверка: `dev.sh test deck_contacts_test deck_tabs_test deck_phone_offline_test remote_phone_link_test fake_phone_test deck_pointer_test` → все зелёные.

## Приёмка
`git diff --stat` — только файлы зоны. Отчёт ≤15 строк по шаблону.
