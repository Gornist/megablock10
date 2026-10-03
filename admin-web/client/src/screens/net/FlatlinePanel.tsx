import { useState } from "react";
import { api } from "../../api/client";
import type { NetRunnerFlagItem } from "../../api/types";
import { AttnRow } from "../../design/AttnRow";
import { AppButton, AppDialog, AppInput, Badge, ErrorNote, Panel } from "../../design/components";
import { formatAgo, shortKey } from "../../format";
import { navigate } from "../../router";
import { numOf, obj, text, useNetCall } from "./netUtil";

/** Одна строка по-русски о том, что произошло в флэтлайне: причина, потерянное, тревога Моста. */
function detailLine(f: NetRunnerFlagItem): string {
  const d = obj(f.detail);
  const parts: string[] = [];
  if (text(d.cause)) parts.push(text(d.cause));
  if (d.disconnect === true) parts.push("обрыв связи");
  const left = numOf(d.left_in_node);
  if (left !== null) parts.push(`осталось в узле: ${left}`);
  if (text(d.alert)) parts.push(`тревога ${text(d.alert)}`);
  return parts.join(" · ");
}

/**
 * Флэтлайн: нетраннеры, заблокированные для входа в Сеть (после смерти в Сети или руками). Решение «пощадить» принимает мастер
 * здесь — коллектор источник правды, Мост читает флаг. Программа персонажа сама не убивает, она только блокирует вход, пока мастер не решит.
 */
export function FlatlinePanel({ flags, reload }: { flags: NetRunnerFlagItem[]; reload: () => void }) {
  const { busy, error, call } = useNetCall(reload);
  const [spare, setSpare] = useState<NetRunnerFlagItem | null>(null);
  const [note, setNote] = useState("");
  const blocked = flags.filter((f) => f.blocked);
  if (blocked.length === 0 && !error) return null;

  return (
    <Panel title={`Флэтлайн: допуск закрыт (${blocked.length})`}>
      {error && <ErrorNote>{error}</ErrorNote>}
      {blocked.map((f) => (
        <AttnRow
          key={f.runnerKey}
          severity="crit"
          title={f.callsign || shortKey(f.runnerKey)}
          detail={
            <>
              {f.reason ?? "заблокирован"}
              {f.node ? ` · узел ${f.node}` : ""}
              {f.terminal ? ` · терминал ${f.terminal}` : ""}
              {detailLine(f) && <span className="hint-text"> · {detailLine(f)}</span>}
            </>
          }
        >
          {!f.bridgeSynced && <Badge tone="warn">Мост ещё не знает</Badge>}
          <span className="attn-time mono">{formatAgo(f.blockedAt)}</span>
          {f.knownPlayer && (
            <button type="button" className="change-toggle" onClick={() => navigate("players", f.runnerKey)}>
              карточка игрока →
            </button>
          )}
          <AppButton variant="primary" disabled={busy} onClick={() => setSpare(f)}>
            пощадить
          </AppButton>
        </AttnRow>
      ))}
      {spare && (
        <AppDialog
          title={`Пощадить «${spare.callsign || shortKey(spare.runnerKey)}»?`}
          body="Допуск в Сеть откроется, персонаж остаётся в игре. Решение запишется в журнал и уйдёт в Мост."
          confirmText="Пощадить"
          onCancel={() => setSpare(null)}
          onConfirm={() => {
            const key = spare.runnerKey;
            setSpare(null);
            void call(() => api.post(`/api/net/runners/${encodeURIComponent(key)}/spare`, { note: note.trim() || undefined })).then(() => setNote(""));
          }}
        >
          <AppInput value={note} onChange={(e) => setNote(e.target.value)} placeholder="основание (по желанию)" aria-label="основание" maxLength={200} />
        </AppDialog>
      )}
    </Panel>
  );
}
