import type { AttentionItem } from "../../apiTypes.js";
import { computeClockAnomalies, computeOutliers, computePulseAnomalies } from "../anomalies.js";
import { withOnline } from "../playerSummary.js";
import type { AttentionRule } from "./context.js";

/** Правила про парк устройств и ход игры в целом: версии, пульс, выбросы, часы. */

const versionKey = (p: { appVersion?: string; wireVersions?: Record<string, number> }) =>
  `${p.appVersion ?? "?"} ${Object.entries(p.wireVersions ?? {}).sort().map(([k, v]) => `${k}${v}`).join(",")}`.trim();

/**
 * Игроки на связи с сборкой, отличной от той, что у большинства: старый APK не понимает новый протокол (чат/звонки/заявки
 * проверяют версию), так что такому игроку нужно обновить приложение. Считаем, только когда у большинства (>50%) версия одна —
 * иначе «эталона» нет, и подсказка была бы шумом.
 */
export const versionMismatch: AttentionRule = ({ players, now, playerName }) => {
  const reporting = withOnline(players, now).filter((p) => p.online && (p.appVersion || p.wireVersions));
  if (reporting.length < 3) return [];
  const counts = new Map<string, number>();
  for (const p of reporting) counts.set(versionKey(p), (counts.get(versionKey(p)) ?? 0) + 1);
  const [majorityKey, majorityCount] = [...counts.entries()].sort((a, b) => b[1] - a[1])[0];
  if (majorityCount * 2 <= reporting.length) return [];

  const wireOf = (key: string) => key.slice(key.indexOf(" ") + 1);
  return reporting
    .filter((p) => versionKey(p) !== majorityKey)
    .map((p): AttentionItem => {
      const protocolDiffers = wireOf(versionKey(p)) !== wireOf(majorityKey);
      return {
        id: `version:${p.publicKeyB64}`,
        kind: "old_version",
        severity: protocolDiffers ? "warn" : "info",
        title: protocolDiffers ? "Другая версия протоколов" : "Другая версия приложения",
        detail: `${p.callsign || playerName(p.publicKeyB64)}: ${versionKey(p)}, у большинства (${majorityCount} из ${reporting.length}) — ${majorityKey}`,
        subjectKey: p.publicKeyB64,
        at: p.lastSeenAt,
      };
    });
};

/** Аномалии пульса игры (lib/anomalies.ts): потеря связи, отказы, лимиты, тормоза, скачок эмиссии. */
export const pulseAnomalies: AttentionRule = ({ db, now }) => computePulseAnomalies(db, now);

/** Игроки-выбросы за 15 минут. */
export const playerOutliers: AttentionRule = ({ db, now, playerName }) => computeOutliers(db, playerName, now);

/** Часы устройств, спешащие относительно сервера. */
export const clockSkew: AttentionRule = ({ db, now, t, playerName }) => computeClockAnomalies(db, playerName, now - t.integrityWindowMs);
