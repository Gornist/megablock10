import { useState } from "react";
import { api } from "../../api/client";
import type { NetSecView } from "../../api/types";
import { POLL_RELAXED_MS } from "../../api/pollIntervals";
import { useApiData } from "../../api/useApiData";
import { AsyncPanel } from "../../design/AsyncPanel";
import { AppButton, AppInput, Badge, ErrorNote, Panel } from "../../design/components";
import { useNetCall } from "./netUtil";

/**
 * Служба безопасности: когда нетраннер дошёл до трейса, Мост шлёт сигнал телефонам фракции-владельца узла (а если владельца
 * нет — фракции по умолчанию). Список телефонов по фракциям коллектор сам собирает из игроков и держит в Мосте актуальным.
 */
export function SecPanel() {
  const { data, error, reload } = useApiData<NetSecView>("/api/net/sec", { pollMs: POLL_RELAXED_MS });
  const { busy, error: saveError, call } = useNetCall(reload);
  const [draft, setDraft] = useState<string | null>(null);

  return (
    <Panel title="Служба безопасности (сигнал СБ)">
      <AsyncPanel data={data} error={error}>
        {(s) => {
          const value = draft ?? s.defaultFaction ?? "";
          const dirty = value.trim() !== (s.defaultFaction ?? "");
          return (
            <>
              <div className="filter-row filter-wrap">
                <AppInput value={value} onChange={(e) => setDraft(e.target.value)} placeholder="фракция СБ по умолчанию" aria-label="фракция СБ по умолчанию" maxLength={64} />
                <AppButton
                  variant="primary"
                  disabled={!dirty || busy}
                  onClick={() =>
                    void call(() => api.put("/api/net/sec", { defaultFaction: value.trim() || null })).then((ok) => {
                      if (ok) setDraft(null);
                    })
                  }
                >
                  сохранить
                </AppButton>
                {!s.sync.connected ? <Badge tone="warn">Мост недоступен — запись в Мост ждёт подключения</Badge> : s.sync.docVer === null ? <Badge tone="warn">в Мосте документа нет — сигнал СБ пока никуда не уходит</Badge> : s.sync.inSync ? <Badge tone="ok">в Мосте актуально</Badge> : <Badge tone="warn">ждёт записи в Мост</Badge>}
              </div>
              {s.sync.lastError && <ErrorNote>{s.sync.lastError}</ErrorNote>}
              {saveError && <ErrorNote>{saveError}</ErrorNote>}
              <p className="hint-text">
                Получатели по фракциям:{" "}
                {s.recipients.length > 0 ? s.recipients.map((r) => `${r.faction} — ${r.count}`).join(" · ") : "ни у одного действующего игрока нет фракции"}. Владельца узла задаёт кнопка «владелец» в таблице узлов.
              </p>
            </>
          );
        }}
      </AsyncPanel>
    </Panel>
  );
}
