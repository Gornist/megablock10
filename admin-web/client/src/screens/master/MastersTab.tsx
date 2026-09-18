import { useState } from "react";
import { api } from "../../api/client";
import { useApiData } from "../../api/useApiData";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AsyncPanel } from "../../design/AsyncPanel";
import { AppButton, AppInput, Field, Panel } from "../../design/components";
import { formatTime } from "../../format";

interface MasterAccount {
  id: string;
  name: string;
  createdAt: number;
}

export function MastersTab() {
  // Список мастеров меняется редко и правится вручную здесь же — polling не нужен, обновляем через reload().
  const { data: masters, error, reload } = useApiData<MasterAccount[]>("/api/masters", { pollMs: false });
  const [name, setName] = useState("");
  const [created, setCreated] = useState<{ name: string; token: string } | null>(null);
  const { busy, error: createError, run } = useAsyncAction({ fallbackError: "не удалось создать" });

  async function create() {
    const res = await run(() => api.post<{ name: string; token: string }>("/api/masters", { name }));
    if (res.ok) {
      setCreated(res.value);
      setName("");
      reload();
    }
  }

  return (
    <>
      <Panel title="Новый мастер">
        <div className="master-form">
          <Field label="Имя">
            <AppInput value={name} onChange={(e) => setName(e.target.value)} placeholder="Мастер Два" />
          </Field>
          {createError && <div className="login-error">{createError}</div>}
          <AppButton variant="primary" onClick={create} disabled={busy || !name.trim()}>
            {busy ? "Создаю…" : "Создать"}
          </AppButton>
        </div>
      </Panel>
      {created && (
        <Panel title="Готово">
          <p>
            Мастер «{created.name}» создан. Токен для входа — <strong className="mono">{created.token}</strong>
          </p>
          <p className="hint-text">Больше нигде не показывается — на сервере хранится только хэш. Передайте его новому мастеру сейчас, здесь и сейчас.</p>
        </Panel>
      )}
      <Panel title="Все мастера">
        <AsyncPanel data={masters} error={error}>
          {(list) =>
            list.map((m) => (
              <div key={m.id} className="slot-row">
                <span>{m.name}</span>
                <span className="hint-text">с {formatTime(m.createdAt)}</span>
              </div>
            ))
          }
        </AsyncPanel>
      </Panel>
    </>
  );
}
