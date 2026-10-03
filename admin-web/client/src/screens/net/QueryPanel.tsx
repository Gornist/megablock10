import { useState } from "react";
import { api } from "../../api/client";
import type { NetDoc, NetState } from "../../api/types";
import { AppButton, AppInput, Badge, ErrorNote, Panel } from "../../design/components";
import { formatAgo } from "../../format";
import { docsOf, newRef, numOf, obj, text, useNetCall } from "./netUtil";

interface Message {
  mid: string;
  from: string;
  text: string;
  at: number | null;
}

const messagesOf = (q: NetDoc): Message[] =>
  (Array.isArray(q.data.messages) ? q.data.messages : []).map((m) => ({ mid: text(obj(m).mid), from: text(obj(m).from), text: text(obj(m).text), at: numOf(obj(m).at) }));

function Thread({ q, reload }: { q: NetDoc; reload: () => void }) {
  const { busy, error, call } = useNetCall(reload);
  const [reply, setReply] = useState("");
  // mid создаётся один раз на ответ и не меняется при повторе после ошибки: Мост не задублирует сообщение (docs/netrun-bridge-protocol.md, 6a).
  const [mid, setMid] = useState(() => newRef("r"));
  const messages = messagesOf(q);
  const open = q.data.state === "open";

  const send = async () => {
    const t = reply.trim();
    if (!t) return;
    if (await call(() => api.post("/api/net/reply", { query: q.id, mid, text: t }))) {
      setReply("");
      setMid(newRef("r"));
    }
  };

  return (
    <div className={`attn-item sev-${open ? "warn" : "info"}`} style={{ flexWrap: "wrap" }}>
      <span className="attn-title">{text(q.data.runner) || q.id}</span>
      <Badge tone={open ? "warn" : "ok"}>{open ? "ждёт ответа" : "отвечено"}</Badge>
      <div className="attn-detail" style={{ flexBasis: "100%" }}>
        {messages.map((m) => (
          <div key={m.mid || m.at}>
            <span className="hint-text">{m.from === "master" ? "мастер" : "нетраннер"} · {formatAgo(m.at)}:</span> {m.text}
          </div>
        ))}
      </div>
      <span className="filter-row" style={{ flexBasis: "100%" }}>
        <AppInput
          value={reply}
          onChange={(e) => setReply(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && void send()}
          placeholder="ответ нетраннеру"
          aria-label={`ответ ${text(q.data.runner) || q.id}`}
          maxLength={2000}
          style={{ flex: 1 }}
        />
        <AppButton variant="primary" disabled={busy || !reply.trim()} onClick={() => void send()}>
          ответить
        </AppButton>
      </span>
      {error && <ErrorNote>{error}</ErrorNote>}
    </div>
  );
}

/** «Запрос к Сети»: канал, по которому нетраннер спрашивает мастера из Сети; открытые вопросы — наверху. */
export function QueryPanel({ state, reload }: { state: NetState; reload: () => void }) {
  const queries = docsOf(state, "net_query").sort((a, b) => Number(b.data.state === "open") - Number(a.data.state === "open") || b.updated - a.updated);
  if (queries.length === 0) return null;
  return (
    <Panel title={`Запрос к Сети (${queries.filter((q) => q.data.state === "open").length} из ${queries.length} ждут ответа)`}>
      {queries.map((q) => (
        <Thread key={q.id} q={q} reload={reload} />
      ))}
    </Panel>
  );
}
