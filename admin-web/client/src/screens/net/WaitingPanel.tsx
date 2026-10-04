import { api } from "../../api/client";
import type { NetState } from "../../api/types";
import { AttnRow } from "../../design/AttnRow";
import { AppButton, Badge, ErrorNote, Panel } from "../../design/components";
import { docsOf, remainingLabel, text, numOf, useNetCall } from "./netUtil";

const KIND_LABEL: Record<string, string> = { flatline: "Флэтлайн", lockdown: "Локдаун", nightmare: "Кошмар" };
const DECISION_LABEL = { approve: "подтвердить", deny: "отклонить" } as const;

/**
 * «Ждём мастера»: запросы к мастеру перед критическим шагом (флэтлайн, локдаун). Не решит мастер — по сроку Мост применит действие
 * по умолчанию само; программа никогда не убивает персонажа без этого шага. Решённые и просроченные не показываем.
 */
export function WaitingPanel({ state, reload }: { state: NetState; reload: () => void }) {
  const { busy, error, call } = useNetCall(reload);
  const pending = docsOf(state, "master_req")
    .filter((d) => d.data.state === "pending")
    .sort((a, b) => (numOf(a.data.expires_at) ?? 0) - (numOf(b.data.expires_at) ?? 0));
  if (pending.length === 0 && !error) return null;

  return (
    <Panel title={`Ждём мастера (${pending.length})`}>
      {error && <ErrorNote>{error}</ErrorNote>}
      {pending.map((r) => {
        const kind = text(r.data.kind);
        const left = remainingLabel(numOf(r.data.expires_at), state.serverNow);
        const def = r.data.default === "deny" ? "deny" : "approve";
        return (
          <AttnRow
            key={r.id}
            severity="crit"
            title={KIND_LABEL[kind] ?? kind}
            detail={
              <>
                {text(r.data.summary) || r.id}
                {r.data.node ? ` · узел ${text(r.data.node)}` : ""}
                <span className="hint-text"> · по сроку — {DECISION_LABEL[def]}</span>
              </>
            }
          >
            {left && <Badge tone="warn">{left}</Badge>}
            <AppButton variant="primary" disabled={busy} onClick={() => void call(() => api.post("/api/net/decide", { req: r.id, decision: "approve" }))}>
              {kind === "flatline" ? "подтвердить флэтлайн" : "подтвердить"}
            </AppButton>
            <AppButton disabled={busy} onClick={() => void call(() => api.post("/api/net/decide", { req: r.id, decision: "deny" }))}>
              отклонить
            </AppButton>
          </AttnRow>
        );
      })}
    </Panel>
  );
}
