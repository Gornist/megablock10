import { useEffect, useRef, useState } from "react";
import { api } from "../../api/client";
import type { Attention } from "../../api/types";
import { useApiData } from "../../api/useApiData";
import { AsyncPanel } from "../../design/AsyncPanel";
import { Badge, Panel } from "../../design/components";
import { formatAgo } from "../../format";
import { navigate } from "../../router";

const NOTIFY_KEY = "mb10.notifyCrit";

function loadNotify(): boolean {
  try {
    return localStorage.getItem(NOTIFY_KEY) === "1";
  } catch {
    return false;
  }
}

/** Короткий сигнал: браузерные уведомления на http по LAN недоступны (нужен HTTPS), а звук и заголовок вкладки работают всегда. */
function beep() {
  try {
    const ctx = new AudioContext();
    const osc = ctx.createOscillator();
    osc.frequency.value = 660;
    osc.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.25);
    osc.onended = () => void ctx.close();
  } catch {
    // нет звука — остаётся заголовок вкладки
  }
}

/**
 * «Требует внимания» — автоподсказки сервера (lib/attention.ts, lib/anomalies.ts): отрицательный
 * баланс, крупные поступления, пропавшие игроки, аномалии пульса и т.п.
 * Клик по строке ведёт к игроку/узлу; «отложить» — «знаю, не мешай» на 30 минут.
 * Новая срочная тревога (при включённом 🔔) даёт звук и метку в заголовке вкладки.
 */
export function AttentionPanel() {
  const [showAll, setShowAll] = useState(false);
  const [notify, setNotify] = useState(loadNotify);
  const { data, error, reload } = useApiData<Attention>(() => (showAll ? "/api/attention?all=1" : "/api/attention"), { pollMs: 10000, key: String(showAll) });
  const counts = data?.counts;

  // Уведомляем только о срочных, которых раньше не видели; первая загрузка лишь запоминает текущие.
  const seen = useRef<Set<string> | null>(null);
  useEffect(() => {
    if (!data) return;
    const crit = data.items.filter((i) => i.severity === "crit");
    if (seen.current && notify) {
      const fresh = crit.filter((i) => !seen.current!.has(i.id));
      if (fresh.length > 0) {
        beep();
        document.title = `(!) ${fresh[0].title}`;
      }
    }
    if (crit.length === 0 && document.title.startsWith("(!)")) document.title = "Мегаблок №10 · Коллектор";
    seen.current = new Set([...(seen.current ?? []), ...crit.map((i) => i.id)]);
  }, [data, notify]);

  const toggleNotify = () => {
    const next = !notify;
    setNotify(next);
    try {
      localStorage.setItem(NOTIFY_KEY, next ? "1" : "0");
    } catch {
      // без сохранения — на этот сеанс достаточно
    }
    if (next) beep(); // жест пользователя разрешает звук, заодно проверка громкости
  };

  const snooze = async (id: string, minutes: number) => {
    await api.post("/api/attention/snooze", { id, minutes });
    reload();
  };

  return (
    <Panel
      title="Требует внимания"
      action={
        <span className="filter-row">
          {counts && counts.crit > 0 && <Badge tone="danger">срочно {counts.crit}</Badge>}
          {counts && counts.warn > 0 && <Badge tone="accent">важно {counts.warn}</Badge>}
          {counts && counts.info > 0 && <Badge tone="info">к сведению {counts.info}</Badge>}
          {(data?.snoozed ?? 0) > 0 && (
            <button type="button" className="change-toggle" onClick={() => setShowAll((v) => !v)}>
              {showAll ? "скрыть отложенные" : `отложено ${data?.snoozed}`}
            </button>
          )}
          <button type="button" className="change-toggle" title="звук и метка в заголовке при новой срочной тревоге" onClick={toggleNotify}>
            {notify ? "🔔 вкл" : "🔕 выкл"}
          </button>
        </span>
      }
    >
      <AsyncPanel data={data} error={error} isEmpty={(d) => d.items.length === 0} emptyLabel="всё спокойно">
        {(d) =>
          d.items.map((i) => {
            const go = i.subjectKey ? () => navigate("players", i.subjectKey!) : i.nodeId ? () => navigate("nodes", i.nodeId!) : undefined;
            return (
              <div key={i.id} className={`attn-item sev-${i.severity} ${go ? "clickable" : ""}`} onClick={go}>
                <span className="attn-title">{i.title}</span>
                <span className="attn-detail">{i.detail}</span>
                <span className="attn-time mono">{formatAgo(i.at)}</span>
                <button
                  type="button"
                  className="change-toggle"
                  title="не показывать 30 минут"
                  onClick={(e) => {
                    e.stopPropagation();
                    void snooze(i.id, 30);
                  }}
                >
                  ⏸ 30 мин
                </button>
              </div>
            );
          })
        }
      </AsyncPanel>
    </Panel>
  );
}
