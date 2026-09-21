/**
 * Типы ответов API. Единственное описание живёт на сервере (server/src/apiTypes.ts):
 * сервер аннотирует им то, что отдаёт, а здесь они лишь реэкспортируются — чисто типовой
 * импорт, в бандл ничего не попадает. Не дублируйте интерфейсы в этом файле.
 */
export type {
  AnnouncementItem,
  AnnouncementRecipient,
  Attention,
  Pulse,
  PulseSample,
  ProvisionItem,
  ProvisionQr,
  ProvisionsResponse,
  AuditResponse,
  BulkPreview,
  ChangeRow,
  CharacterSnapshot,
  Economy,
  EventsResponse,
  FactionRow,
  Meta,
  NodeDetail,
  NodeSummary,
  Overview,
  PlayerListItem,
  SlotRegistryItem,
  TargetSelector,
  Transfer,
  WatchItem,
} from "../../../server/src/apiTypes";
