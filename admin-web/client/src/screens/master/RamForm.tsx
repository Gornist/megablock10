import { useState } from "react";
import { api } from "../../api/client";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppInput, Field, Panel } from "../../design/components";
import { QrPanel, type QrResult } from "./common";

export function RamForm() {
  const [delta, setDelta] = useState("1");
  const [result, setResult] = useState<QrResult | null>(null);
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось сгенерировать" });

  async function submit() {
    const res = await run(() => api.post<{ token: string; qr: string; qrImage: string }>("/api/master/ram", { delta: Number(delta) || 1 }));
    if (res.ok) setResult(res.value);
  }

  return (
    <>
      <Panel title="RAM-апгрейд">
        <div className="master-form">
          <p className="hint-text">Каждый QR одноразовый на устройство игрока — генерируйте новый для каждой выдачи.</p>
          <Field label="Прибавка к RAM, ячеек">
            <AppInput value={delta} onChange={(e) => setDelta(e.target.value.replace(/\D/g, ""))} placeholder="1" />
          </Field>
          {error && <div className="login-error">{error}</div>}
          <AppButton variant="primary" onClick={submit} disabled={busy || !(Number(delta) > 0)}>
            {busy ? "Генерирую…" : "Показать QR"}
          </AppButton>
        </div>
      </Panel>
      {result && <QrPanel result={result} caption={`+${delta} RAM`} />}
    </>
  );
}
