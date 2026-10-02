/**
 * Быстрые события «Сети», которые видит только мастер, а не площадка (`alert.master` — звонок мастеру, docs/netrun-world-records.md §3).
 * В памяти процесса, как счётчики пульса: событие живёт секунды, на диск ему незачем, а «внимание» держит его на экране недолго.
 */
export interface MasterAlertEvent {
  id: string;
  at: number;
  node: string | null;
  terminal: string | null;
  session: string | null;
}

/** Сколько тревога мастеру висит в «Требует внимания» — потом считается прочитанной (мастер её видел или не был у экрана; повторное событие поднимет заново). */
export const MASTER_ALERT_SHOW_MS = 10 * 60 * 1000;
const KEEP = 50;

let alerts: MasterAlertEvent[] = [];

export function recordMasterAlert(e: MasterAlertEvent): void {
  alerts = [e, ...alerts].slice(0, KEEP);
}

export function recentMasterAlerts(now: number): MasterAlertEvent[] {
  return alerts.filter((a) => now - a.at <= MASTER_ALERT_SHOW_MS);
}

/** Только для тестов: у каждого теста — чистая картина. */
export function resetWorldEventLog(): void {
  alerts = [];
}
