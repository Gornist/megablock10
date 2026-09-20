/**
 * Типы ответов API. Единственное описание живёт на сервере (server/src/apiTypes.ts):
 * сервер аннотирует им то, что отдаёт, а здесь они лишь реэкспортируются — чисто типовой
 * импорт, в бандл ничего не попадает. Не дублируйте интерфейсы в этом файле.
 */
export type {
  AnnouncementItem,
  AnnouncementRecipient,
  Attention,
  AttentionItem,
  AuditRecord,
  AuditResponse,
  BulkPreview,
  ChangeKind,
  ChangeRow,
  CharacterSnapshot,
  Counters,
  DaemonEntry,
  Economy,
  EventsResponse,
  FactionEvents,
  FactionRow,
  HumanChange,
  Meta,
  NodeDetail,
  NodeSummary,
  Overview,
  PlayerListItem,
  Severity,
  ShardEntry,
  SlotRegistryItem,
  TargetSelector,
  Transfer,
  WatchItem,
} from "../../../server/src/apiTypes";
