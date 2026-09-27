import { useState } from "react";
import type { DisplayItem, DisplaySecretResponse } from "../api/types";
import { useApiData } from "../api/useApiData";
import { POLL_LIVE_MS } from "../api/pollIntervals";
import { AsyncPanel } from "../design/AsyncPanel";
import { AppButton, Panel, StatTile } from "../design/components";
import { DisplayCard } from "./displays/DisplayCard";
import { DisplayForm, SecretPanel } from "./displays/DisplayForm";
import { DisplayPushDialog } from "./displays/DisplayPushDialog";
import type { DisplaySource } from "./displays/displayUtil";

/**
 * Электронные QR-точки (ESP32 + e-paper, docs/displays.md): реестр, состояние каждой, команды. Отправка QR — отсюда («Повторить»)
 * и из Мастерской / карточки узла («На дисплей»); сервер сам рисует кадр и сам ходит к дисплеям.
 */
export function DisplaysScreen() {
  const { data: displays, error, reload } = useApiData<DisplayItem[]>("/api/displays", { pollMs: POLL_LIVE_MS });
  const [form, setForm] = useState<"new" | DisplayItem | null>(null);
  const [secret, setSecret] = useState<DisplaySecretResponse | null>(null);
  const [push, setPush] = useState<{ source: DisplaySource; title: string } | null>(null);

  const count = (s: DisplayItem["status"]) => (displays ?? []).filter((d) => d.status === s).length;

  return (
    <div className="screen-grid">
      <p className="hint-text master-intro">
        Физические QR-точки: дисплей показывает тот же QR, что печатается, — игрок сканирует как обычно. Отправить QR на дисплей — кнопка
        «На дисплей» у готового QR в Мастерской или в карточке узла. Без сети дисплей продолжает показывать последний кадр.
      </p>
      <div className="stat-row">
        <StatTile label="на связи" value={count("ONLINE")} tone="ok" />
        <StatTile label="обновляются" value={count("UPDATING")} tone="accent" />
        <StatTile label="ошибка" value={count("ERROR")} tone="danger" />
        <StatTile label="нет связи" value={count("OFFLINE")} />
      </div>
      {secret && <SecretPanel result={secret} onClose={() => setSecret(null)} />}
      {form && (
        <DisplayForm
          key={form === "new" ? "new" : form.id}
          editing={form === "new" ? undefined : form}
          onCreated={(r) => {
            setForm(null);
            setSecret(r);
            reload();
          }}
          onSaved={() => {
            setForm(null);
            reload();
          }}
          onCancel={() => setForm(null)}
        />
      )}
      <Panel title={`Дисплеи${displays ? ` (${displays.length})` : ""}`} action={<AppButton onClick={() => setForm("new")}>+ дисплей</AppButton>}>
        <AsyncPanel data={displays} error={error} isEmpty={(d) => d.length === 0} emptyLabel="дисплеев пока нет — добавьте первый">
          {(list) => (
            <div className="display-grid">
              {list.map((d) => (
                <DisplayCard
                  key={d.id}
                  display={d}
                  onChanged={reload}
                  onEdit={() => setForm(d)}
                  onSecret={(r) => {
                    setSecret(r);
                    reload();
                  }}
                  onPush={(source, title) => setPush({ source, title })}
                />
              ))}
            </div>
          )}
        </AsyncPanel>
      </Panel>
      {push && (
        <DisplayPushDialog
          source={push.source}
          title={push.title}
          onClose={() => {
            setPush(null);
            reload();
          }}
        />
      )}
    </div>
  );
}
