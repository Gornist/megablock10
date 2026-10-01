# rules — общие правила игры

Чистый Kotlin/JVM без Android (`./gradlew :rules:test :rules:detekt :rules:animalsnifferMain`). Зависит только от `:kit`.
Отдельно от `:kit`, потому что kit — механика без знаний об игре, а здесь именно игра (решение M1 плана «Сети»).

| Что | Где |
|---|---|
| `Tier`, `DaemonEffect`, `Daemon`, `BreachOutcome` | модели правил; в `:app` на них псевдонимы (`typealias`) в пакете `breach`, импорты не менялись |
| `ItemPayloadCodec`, `ShardPayload` | поля предмета в карточке передачи (`ITEM2|…|payload`); `app/items/ItemPayload` переводит `Mb10Qr.Shard` в `ShardPayload` |
| `SecAlertRules.decide`, `AlertPlan` | гейтинг и содержимое сигнала СБ (ревизия v9 §4); `SecAlertStore.decide` в приложении — тонкая передача |

Формат не менять без поднятия версии (`WireVersion`): байты уходят в подписанные карточки. Эталонные строки — `RulesGoldenTest` и
`app/…/items/ItemCardGoldenTest`. Тексты для игрока (`DaemonEffect.label`, `cellsLabel`) остаются в приложении.
