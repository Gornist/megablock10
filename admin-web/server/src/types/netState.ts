// ── «Сеть»: состояние Моста для экрана (docs/netrun-bridge-protocol.md) ──

/** Документ Моста как есть: type+id, версия и данные (схема — по типу, раздел 5 протокола). */
export interface NetDoc {
  type: string;
  id: string;
  ver: number;
  created: number;
  updated: number;
  data: Record<string, unknown>;
}

/**
 * Снимок «Сети» для экрана. docs — по типам (node, node_cfg, session, deck, terminal, alert, master_req, net_query, template,
 * settings) и только пока Мост на связи: нет связи — docs пуст, экран пишет «Мост недоступен», а не показывает старое как живое.
 */
export interface NetState {
  /** false — BRIDGE_MASTER_KEY не задан, функции Моста выключены. */
  configured: boolean;
  bridge: "disabled" | "connecting" | "connected" | "down";
  /** Почему нет связи (последняя ошибка), если она известна. */
  error: string | null;
  info: { version: string; worldPub: string; seq: number } | null;
  docs: Record<string, NetDoc[]>;
  /** Часы сервера: сроки (expires_at, lockdown_until) экран считает от них, а не от часов браузера. */
  serverNow: number;
}

/** Получатели сигнала СБ: фракция по умолчанию, сколько телефонов получит сигнал по каждой фракции и состояние документа settings/sec в Мосте. */
export interface NetSecView {
  defaultFaction: string | null;
  recipients: { faction: string; count: number }[];
  sync: {
    /** Мост на связи; нет — остальное неизвестно, запись ждёт подключения. */
    connected: boolean;
    /** Документ в Мосте совпадает с составом фракций коллектора. */
    inSync: boolean;
    /** Версия документа в Мосте; null — документа нет (сигнал СБ пока никуда не уходит). */
    docVer: number | null;
    lastError: string | null;
  };
}

/** Предмет, лежащий в узле Сети (документ item с owner node:<узел>): без payload — тело шарда в списке не нужно. */
export interface NodeStockItem {
  id: string;
  ver: number;
  kind: string;
  /** Заголовок шарда или имя демона — как разобрал Мост; пусто, если не разобралось. */
  title: string;
  tier: number | null;
  /** Эффект демона. */
  effect: string | null;
  origin: string;
}

export interface NodeStockView {
  node: string;
  /** Запас эдди в узле; null — узла нет в копии Моста. */
  eddies: number | null;
  items: NodeStockItem[];
}

/** Ответ Моста на наполнение/разгрузку узла: какие предметы затронуты, остаток эдди, и был ли это повтор по тому же rid. */
export interface NetStockResult {
  node: string;
  items: string[];
  eddies: number;
  replayed?: boolean;
}
