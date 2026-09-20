import { useState } from "react";
import { api } from "../api/client";
import type { AnnouncementItem, AnnouncementRecipient, FactionRow } from "../api/types";
import { useApiData } from "../api/useApiData";
import { useAsyncAction } from "../api/useAsyncAction";
import { AsyncPanel } from "../design/AsyncPanel";
import { ShareBar } from "../design/charts";
import { AppButton, AppSelect, Badge, EmptyState, Field, Panel } from "../design/components";
import { formatDateTime } from "../format";

const MAX_TEXT = 500;

interface Preview {
  count: number;
  target: string;
  recipients: string[];
}

/**
 * Объявления мастера игрокам: сообщение всем или одной фракции — приходит на
 * телефон при ближайшем опросе коллектора (≤30с), там показывается окном и
 * системным уведомлением. История показывает, сколько адресатов уже получили.
 */
export function AnnouncementsScreen() {
  const { data: factions } = useApiData<FactionRow[]>("/api/factions", { pollMs: false });
  const { data: history, error, reload } = useApiData<AnnouncementItem[]>("/api/announcements", { pollMs: 5000 });
  const [text, setText] = useState("");
  const [target, setTarget] = useState("all");
  const [preview, setPreview] = useState<Preview | null>(null);
  const [sentInfo, setSentInfo] = useState<string | null>(null);
  const { busy, error: actionError, run } = useAsyncAction({ fallbackError: "не удалось отправить" });

  const body = () => (target === "all" ? { text, all: true } : { text, faction: target.slice("f:".length) });
  const trimmed = text.trim();

  async function doPreview() {
    setSentInfo(null);
    const res = await run(() => api.post<Preview>("/api/announcements", { ...body(), dryRun: true }));
    if (res.ok) setPreview(res.value);
  }

  async function send() {
    const res = await run(() => api.post<{ count: number; target: string }>("/api/announcements", body()));
    if (res.ok) {
      setSentInfo(`Отправлено: ${res.value.target}, ${res.value.count} чел.`);
      setText("");
      setPreview(null);
      reload();
    }
  }

  return (
    <div className="screen-grid">
      <Panel title="Новое объявление">
        <div className="bulk-form">
          <Field label="Кому">
            <AppSelect
              value={target}
              onChange={(e) => {
                setTarget(e.target.value);
                setPreview(null);
              }}
            >
              <option value="all">всем игрокам</option>
              {(factions ?? []).map((f) => (
                <option key={f.faction} value={`f:${f.faction}`}>
                  фракции «{f.faction || "без фракции"}» ({f.players})
                </option>
              ))}
            </AppSelect>
          </Field>
          <Field label={`Текст (${text.length}/${MAX_TEXT})`}>
            <textarea
              className="app-input master-textarea wide"
              maxLength={MAX_TEXT}
              value={text}
              onChange={(e) => {
                setText(e.target.value);
                setPreview(null);
              }}
              placeholder="Например: «Сбор у главного входа в 22:00»"
            />
          </Field>
          {actionError && <div className="login-error">{actionError}</div>}
          {sentInfo && <div className="hint-text">{sentInfo}</div>}
          <div className="bulk-grid">
            <AppButton onClick={doPreview} disabled={busy || !trimmed}>
              Кому уйдёт?
            </AppButton>
            <AppButton variant="primary" onClick={send} disabled={busy || !trimmed || !preview}>
              {busy ? "…" : `Отправить${preview ? ` (${preview.count})` : ""}`}
            </AppButton>
          </div>
          {preview && (
            <p className="hint-text">
              {preview.target}: {preview.count} чел. — {preview.recipients.slice(0, 12).join(", ")}
              {preview.recipients.length > 12 ? "…" : ""}. Нажмите «Отправить», чтобы подтвердить.
            </p>
          )}
        </div>
      </Panel>

      <Panel title="История рассылок">
        <AsyncPanel data={history} error={error} isEmpty={(d) => d.length === 0} emptyLabel="объявлений пока не было">
          {(list) => list.map((a) => <AnnouncementRow key={a.id} item={a} />)}
        </AsyncPanel>
      </Panel>
    </div>
  );
}

function AnnouncementRow({ item }: { item: AnnouncementItem }) {
  const [open, setOpen] = useState(false);
  const missing = item.recipients - item.delivered;

  return (
    <div className="attn-item clickable" style={{ flexWrap: "wrap" }} onClick={() => setOpen((v) => !v)}>
      <span className="attn-time mono">{formatDateTime(item.at)}</span>
      <span className="attn-detail">«{item.text}»</span>
      <span>
        <ShareBar value={item.delivered} max={item.recipients} tone="ok" /> <span className="mono">{item.delivered}/{item.recipients}</span>{" "}
        {missing > 0 ? <Badge tone="accent">не дошло: {missing}</Badge> : <Badge tone="ok">доставлено</Badge>}
      </span>
      <span className="attn-time">{item.masterName}</span>
      {open && <RecipientList id={item.id} />}
    </div>
  );
}

/** Кому дошло, кому нет — недоставленные первыми (порядок задаёт сервер). Опрашивается, пока строка раскрыта. */
function RecipientList({ id }: { id: string }) {
  const { data } = useApiData<AnnouncementRecipient[]>(`/api/announcements/${id}/recipients`, { pollMs: 5000 });
  return (
    <div style={{ flexBasis: "100%" }} className="hint-text">
      {data === null ? (
        <EmptyState>загрузка…</EmptyState>
      ) : (
        data.map((r) => (
          <Badge key={r.publicKeyB64} tone={r.delivered ? "ok" : "accent"}>
            {r.callsign} {r.delivered ? "✓" : "…"}
          </Badge>
        ))
      )}
    </div>
  );
}
