import { api } from "../../api/client";
import type { NetState } from "../../api/types";
import { AttnRow } from "../../design/AttnRow";
import { AppButton, ErrorNote, Panel } from "../../design/components";
import { formatAgo } from "../../format";
import { alertTone, docsOf, text, useNetCall } from "./netUtil";

/**
 * Тревоги Моста: аудитор (рассинхрон предметов и эдди, «аудитор молчит») мастеру важно увидеть сразу. «Принять» снимает тревогу
 * в Мосте (с её версией: если она успела измениться, Мост откажет и экран покажет свежую).
 */
export function AlertsPanel({ state, reload }: { state: NetState; reload: () => void }) {
  const { busy, error, call } = useNetCall(reload);
  const alerts = docsOf(state, "alert").sort((a, b) => b.updated - a.updated);
  if (alerts.length === 0 && !error) return null;
  return (
    <Panel title={`Тревоги Сети (${alerts.length})`}>
      {error && <ErrorNote>{error}</ErrorNote>}
      {alerts.map((a) => {
        const kind = text(a.data.kind) || "без вида";
        return (
          <AttnRow key={a.id} severity={alertTone(kind) === "danger" ? "crit" : "warn"} title={kind} detail={text(a.data.msg) || a.id}>
            <span className="attn-time mono">{formatAgo(a.created)}</span>
            <AppButton disabled={busy} onClick={() => void call(() => api.delete(`/api/net/alerts/${encodeURIComponent(a.id)}?ver=${a.ver}`))}>
              принять
            </AppButton>
          </AttnRow>
        );
      })}
    </Panel>
  );
}
