// ── «Сеть» → площадка: быстрые события на точки (docs/netrun-world-records.md, §3) ──

export interface WorldEventKindInfo {
  kind: "run.enter" | "run.exit" | "trace.level" | "ice.hunt" | "flatline" | "lockdown" | "alert.master";
  label: string;
  /** Когда возникает. */
  when: string;
  /** На какие точки идёт: по терминалу и/или по узлу Сети (alert.master — ни на какие, только панель мастера). */
  byTerminal: boolean;
  byNode: boolean;
}

export interface WorldEventActionItem {
  kind: WorldEventKindInfo["kind"];
  clipId: string | null;
  clipName: string | null;
  /** null — громкость по умолчанию (80). */
  volume: number | null;
  chime: boolean;
  enabled: boolean;
}

/** Точка ↔ узел и/или терминал Сети: по этой связи коллектор решает, кому идёт событие. */
export interface NetPointLinkItem {
  displayId: string;
  displayName: string;
  netNode: string | null;
  terminal: string | null;
}

export interface WorldEventsConfig {
  kinds: WorldEventKindInfo[];
  actions: WorldEventActionItem[];
  links: NetPointLinkItem[];
}

export interface WorldEventsTestResult {
  accepted: number;
  /** Точки, на которые ушло объявление; пусто — нет настройки, связи точки или звуковой точки. */
  playedOn: string[];
}
