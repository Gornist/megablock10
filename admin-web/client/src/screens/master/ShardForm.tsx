import { useState } from "react";
import { api } from "../../api/client";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppInput, Field, Panel } from "../../design/components";
import { QrPanel, type QrResult, type TierName, TierPicker } from "./common";
import { EMPTY_SHARD_DRAFT, ShardFields, shardDraftToPayload, type ShardDraft } from "./ShardFields";

export function ShardForm() {
  const [id, setId] = useState("");
  const [tier, setTier] = useState<TierName>("BASE");
  const [draft, setDraft] = useState<ShardDraft>(EMPTY_SHARD_DRAFT);
  const [result, setResult] = useState<QrResult | null>(null);
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось сгенерировать" });

  async function submit() {
    const res = await run(() =>
      api.post<{ shardId: string; qr: string; qrImage: string }>("/api/master/shards", {
        id: id || undefined,
        tier,
        ...shardDraftToPayload(draft),
      }),
    );
    if (res.ok) setResult(res.value);
  }

  return (
    <>
      <Panel title="Шард">
        <div className="master-form">
          <Field label="id (можно не менять)">
            <AppInput value={id} onChange={(e) => setId(e.target.value)} placeholder="shard-xxxxxxxx" />
          </Field>
          <Field label="Тир (длина цели расшифровки)">
            <TierPicker value={tier} onChange={setTier} />
          </Field>
          <ShardFields value={draft} onChange={(patch) => setDraft((d) => ({ ...d, ...patch }))} />
          {error && <div className="login-error">{error}</div>}
          <AppButton variant="primary" onClick={submit} disabled={busy || !draft.title || !draft.body}>
            {busy ? "Генерирую…" : "Показать QR"}
          </AppButton>
        </div>
      </Panel>
      {result && <QrPanel result={result} caption={draft.title} />}
    </>
  );
}
