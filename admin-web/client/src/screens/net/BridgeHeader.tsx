import { useState } from "react";
import { api } from "../../api/client";
import type { NetState } from "../../api/types";
import { AppButton, AppDialog, Badge, ErrorNote, Panel } from "../../design/components";
import { docsOf, obj, useNetCall } from "./netUtil";

const STATUS: Record<NetState["bridge"], { label: string; tone: "ok" | "danger" | "warn" | "neutral" }> = {
  connected: { label: "Мост на связи", tone: "ok" },
  connecting: { label: "подключаемся к Мосту…", tone: "warn" },
  down: { label: "Мост недоступен", tone: "danger" },
  disabled: { label: "Мост не настроен", tone: "neutral" },
};

/** Шапка: состояние Моста, пауза всей Сети и рубильник связи с площадкой. Без Моста вместо данных — понятная плашка, а не старый снимок. */
export function BridgeHeader({ state, reload }: { state: NetState; reload: () => void }) {
  const { busy, error, call } = useNetCall(reload);
  const [confirmPause, setConfirmPause] = useState(false);
  const global = obj(docsOf(state, "settings").find((d) => d.id === "global")?.data);
  const paused = global.paused === true;
  const venueLink = global.venue_link !== false;
  const st = STATUS[state.bridge];
  const live = state.bridge === "connected";

  return (
    <Panel
      title="Сеть"
      action={
        <span className="filter-row filter-wrap">
          <Badge tone={st.tone}>{st.label}</Badge>
          {live && paused && <Badge tone="danger">Сеть на паузе</Badge>}
          {live && !venueLink && <Badge tone="warn">связь с площадкой выключена</Badge>}
          {live && state.info && <span className="hint-text mono">v{state.info.version} · seq {state.info.seq}</span>}
          {live && (
            <>
              <AppButton variant={paused ? "primary" : "danger"} disabled={busy} onClick={() => (paused ? void call(() => api.post("/api/net/pause", { on: false })) : setConfirmPause(true))}>
                {paused ? "снять паузу" : "пауза Сети"}
              </AppButton>
              <AppButton disabled={busy} onClick={() => void call(() => api.post("/api/net/link", { on: !venueLink }))}>
                {venueLink ? "отключить площадку" : "включить площадку"}
              </AppButton>
            </>
          )}
        </span>
      }
    >
      {state.bridge === "disabled" && (
        <p className="hint-text">Адрес и ключ Моста задаются переменными окружения коллектора BRIDGE_URL и BRIDGE_MASTER_KEY. Пока их нет, остальное в коллекторе работает как обычно, а настройки площадки и СБ ниже сохраняются.</p>
      )}
      {(state.bridge === "down" || state.bridge === "connecting") && (
        <p className="hint-text">
          Мост недоступен — данных Сети нет, старые не показываем{state.error ? ` (${state.error})` : ""}. Коллектор переподключается сам; настройки площадки и СБ ниже сохраняются и уйдут в Мост при подключении.
        </p>
      )}
      {error && <ErrorNote>{error}</ErrorNote>}
      {confirmPause && (
        <AppDialog
          title="Поставить всю Сеть на паузу?"
          body="Забеги остановятся, пока вы не снимете паузу. Игроки в очках увидят «Сеть на паузе»."
          confirmText="Пауза"
          confirmVariant="danger"
          onCancel={() => setConfirmPause(false)}
          onConfirm={() => {
            setConfirmPause(false);
            void call(() => api.post("/api/net/pause", { on: true }));
          }}
        />
      )}
    </Panel>
  );
}
