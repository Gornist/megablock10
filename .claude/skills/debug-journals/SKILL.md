---
name: debug-journals
description: Разбор красного сценария e2e или сбоя приложения по журналам Mb10Log — где лежат журналы, ключевые события, как сравнить с main. Использовать перед любой гипотезой о причине сбоя.
---

## Отладка: сначала журналы, потом гипотезы

- Журнал приложения — события `Mb10Log` (`name key=value`), на устройстве `Android/data/com.megablok10.app/files/logs/`,
  на стенде `journal_cat <serial>`; красные сценарии кладут его в `$E2E_DIR/journals/`, CI печатает прямо в лог job
  (шаг «Журналы красных сценариев»). Прежде чем чинить — найти в журнале строку, которая объясняет сбой.
- Разовый красный — не «флейк»: сравнить с прогоном на `main` (запустить `e2e.yml` на `main`), найти причину.
- Ключевые события: `chat.send_direct … outcome=`, `send.not_reached`, `sync.ok|sync.unreachable`, `peer.found|peer.static|peer.server_hints`,
  `chat.start|chat.stop`, `=== ЗАПУСК ПРОЦЕССА ===`, `Snapshot` (раз в 30 с: Wi-Fi, очередь).

