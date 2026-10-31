# rules — общие правила игры

Чистый Kotlin/JVM без Android (`./gradlew :rules:test :rules:detekt :rules:animalsnifferMain`). Зависит только от `:kit`; подключают `:app` и `:netrun-bridge` (Мост берёт отсюда те же правила, что и телефон).
Отдельно от `:kit`, потому что kit — механика без знаний об игре, а здесь именно игра (решение M1 плана «Сети»). Те же ограничения, что у kit: только API Android 8.0 (Animal Sniffer), без JSON-библиотек в основном коде.

| Что | Где (`com.megablok10.rules`) |
|---|---|
| Взлом: `Tier`, `Daemon`, `DaemonEffect`, `BreachOutcome`, `BreachGrid`/генератор сетки, `BreachAttemptState`, `BreachRun` (ход попытки: тап/тик/итог), правило чередования строка/столбец (`BreachRules`), `BreachAutoSolver` | модели и чистая логика взлома; в `:app` на них псевдонимы (`typealias`) в пакете `breach` (`BreachAliases.kt`, `Tier.kt`, `DaemonEffect.kt`), импорты не менялись |
| `BreachTierParams`, `BreachParams`, `BreachConstants` | числа взлома по тирам (сетка, таймер, мёртвые клетки, замок хранилища, запас буфера) и общие (остывание узла, JITTER) |
| `Container`, `LootSlot`, `SlotPicker`, `ContainerEddies`, `DecryptRules`, `IceLines`, `RamCapacity` | контейнер и его слоты, выбор слота под извлечение, эдди за взлом, правила расшифровки шардов, реплики защиты, RAM деки (нужна и телефону, и Мосту) |
| `ItemPayloadCodec`, `ShardPayload` | поля предмета в карточке передачи (`ITEM2|…|payload`); `app/items/ItemPayload` переводит `Mb10Qr.Shard` в `ShardPayload` |
| `SecAlertRules.decide`, `AlertPlan`, `SecAlertAggregator` | гейтинг, содержимое и склейка сигналов СБ (ревизия v9 §4); `SecAlertStore.decide` в приложении — тонкая передача |

Формат не менять без поднятия версии (`WireVersion`): байты уходят в подписанные карточки. Эталонные строки — `RulesGoldenTest` и
`app/…/items/ItemCardGoldenTest`. Тексты для игрока (`DaemonEffect.label`, `cellsLabel`) остаются в приложении.

## Файлы, общие с другими зонами

- **Числа взлома для Godot** — `netrun/data/rules/breach.json` (и golden-наборы `netrun/tests/fixtures/breach_golden.json`): источник правды — константы здесь, `BreachJsonTest` и `BreachGoldenTest` сверяют файлы с кодом (разошлись — красный CI с этой стороны). `UPDATE_NETRUN_JSON=1` перегенерирует файлы (через `scripts/dbx.sh --env`); diff идёт в коммит вместе с правкой кода.
- **Общие JSON-векторы контрактов** — `rules/src/test/resources/contracts/*.json` (подпись записей, карточки, QR, крипто лута, короткий код выдачи, операции Моста): известные ответы, которые сверяют приложение, коллектор и Мост. Состав, читатели и правила файлов — [contracts/README.md](src/test/resources/contracts/README.md).
