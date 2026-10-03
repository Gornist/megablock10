import { useState } from "react";
import { api } from "../../api/client";
import type { NetRunnerFlagItem } from "../../api/types";
import { POLL_RELAXED_MS } from "../../api/pollIntervals";
import { useApiData } from "../../api/useApiData";
import { AppButton, AppDialog, AppInput, Badge, ErrorNote, Panel } from "../../design/components";
import { formatAgo } from "../../format";
import { useNetCall } from "../net/netUtil";

type Flag = NetRunnerFlagItem | { blocked: false };

/**
 * Допуск игрока в Сеть (VR-забеги): открыт или закрыт. Закрывает Мост после флэтлайна или мастер руками; «пощадить» открывает.
 * Коллектор — источник правды: решение пишется здесь и догоняется в Мосте при следующем подключении.
 */
export function NetAccessPanel({ publicKeyB64 }: { publicKeyB64: string }) {
  const { data, error, reload } = useApiData<Flag>(`/api/net/runners/${encodeURIComponent(publicKeyB64)}`, { pollMs: POLL_RELAXED_MS });
  const { busy, error: actionError, call } = useNetCall(reload);
  const [dialog, setDialog] = useState<"spare" | "block" | null>(null);
  const [text, setText] = useState("");

  if (error) return <ErrorNote>{error}</ErrorNote>;
  if (!data) return null;
  const flag = data.blocked ? (data as NetRunnerFlagItem) : null;
  const base = `/api/net/runners/${encodeURIComponent(publicKeyB64)}`;
  const close = () => {
    setDialog(null);
    setText("");
  };

  return (
    <Panel
      title="Допуск в Сеть"
      action={
        <span className="filter-row filter-wrap">
          {flag ? <Badge tone="danger">закрыт</Badge> : <Badge tone="ok">открыт</Badge>}
          {flag ? (
            <AppButton variant="primary" disabled={busy} onClick={() => setDialog("spare")}>пощадить</AppButton>
          ) : (
            <AppButton variant="danger" disabled={busy} onClick={() => setDialog("block")}>закрыть допуск</AppButton>
          )}
        </span>
      }
    >
      {flag && (
        <p className="hint-text">
          {flag.reason ?? "заблокирован"}
          {flag.node ? ` · узел ${flag.node}` : ""}
          {flag.blockedAt ? ` · ${formatAgo(flag.blockedAt)}` : ""}
          {!flag.bridgeSynced ? " · Мост ещё не знает об этом решении" : ""}
        </p>
      )}
      {!flag && <p className="hint-text">Игрок может входить в Сеть. Допуск закрывается автоматически после флэтлайна или вручную здесь.</p>}
      {actionError && <ErrorNote>{actionError}</ErrorNote>}
      {dialog && (
        <AppDialog
          title={dialog === "spare" ? "Пощадить нетраннера?" : "Закрыть допуск в Сеть?"}
          body={dialog === "spare" ? "Допуск откроется, решение запишется в журнал и уйдёт в Мост." : "Игрок не сможет войти в Сеть, пока вы не пощадите его. Основание обязательно."}
          confirmText={dialog === "spare" ? "Пощадить" : "Закрыть допуск"}
          confirmVariant={dialog === "spare" ? "primary" : "danger"}
          confirmDisabled={dialog === "block" && !text.trim()}
          onCancel={close}
          onConfirm={() => {
            const which = dialog;
            const t = text.trim();
            close();
            void call(() => (which === "spare" ? api.post(`${base}/spare`, { note: t || undefined }) : api.post(`${base}/block`, { reason: t })));
          }}
        >
          <AppInput value={text} onChange={(e) => setText(e.target.value)} placeholder={dialog === "spare" ? "основание (по желанию)" : "основание (обязательно)"} aria-label="основание" maxLength={200} />
        </AppDialog>
      )}
    </Panel>
  );
}
