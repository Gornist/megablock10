import { useState } from "react";
import { api } from "../../api/client";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppInput, AppSelect, Panel } from "../../design/components";
import { shortKey } from "../../format";

const OVERRIDE_FIELDS = ["balance", "ramCapacity", "callsign", "faction"];

export function OverridePanel({ publicKeyB64, onDone }: { publicKeyB64: string; onDone: () => void }) {
  const [field, setField] = useState(OVERRIDE_FIELDS[0]);
  const [mode, setMode] = useState<"set" | "add">("set");
  const [value, setValue] = useState("");
  const [reason, setReason] = useState("");
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось сохранить правку" });

  // «Прибавить» имеет смысл только для чисел (эдди, RAM); позывной и фракцию можно только задать.
  const numeric = field === "balance" || field === "ramCapacity";

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const res = await run(() => api.post(`/api/players/${encodeURIComponent(publicKeyB64)}/override`, { field, newValue: value, reason, mode: numeric ? mode : "set" }));
    if (res.ok) {
      setValue("");
      setReason("");
      onDone();
    }
  }

  return (
    <Panel title="Ручная правка">
      <form onSubmit={submit} className="override-form">
        <AppSelect value={field} onChange={(e) => setField(e.target.value)}>
          {OVERRIDE_FIELDS.map((f) => (
            <option key={f} value={f}>
              {f}
            </option>
          ))}
        </AppSelect>
        {numeric && (
          <AppSelect value={mode} onChange={(e) => setMode(e.target.value as "set" | "add")}>
            <option value="set">установить</option>
            <option value="add">прибавить</option>
          </AppSelect>
        )}
        <AppInput placeholder={numeric && mode === "add" ? "на сколько (можно −)" : "новое значение"} value={value} onChange={(e) => setValue(e.target.value)} required />
        <AppInput placeholder="основание (обязательно)" value={reason} onChange={(e) => setReason(e.target.value)} required />
        <AppButton type="submit" variant="primary" disabled={busy}>
          {busy ? "…" : "Применить"}
        </AppButton>
      </form>
      {error && <div className="login-error">{error}</div>}
      <p className="hint-text">
        Уходит игроку как MASTER_OVERRIDE при следующем опросе коллектора его устройством (раз в ~30с), видна в истории наравне с игровыми записями.
        Ключ: {shortKey(publicKeyB64, 16)}
      </p>
    </Panel>
  );
}
