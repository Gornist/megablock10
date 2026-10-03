import { POLL_LIVE_MS } from "../api/pollIntervals";
import type { NetRunnerFlagItem, NetState } from "../api/types";
import { useApiData } from "../api/useApiData";
import { ErrorNote } from "../design/components";
import { AlertsPanel } from "./net/AlertsPanel";
import { BridgeHeader } from "./net/BridgeHeader";
import { FlatlinePanel } from "./net/FlatlinePanel";
import { NodesPanel } from "./net/NodesPanel";
import { QueryPanel } from "./net/QueryPanel";
import { SecPanel } from "./net/SecPanel";
import { SessionsPanel } from "./net/SessionsPanel";
import { TemplatesPanel } from "./net/TemplatesPanel";
import { TerminalsPanel } from "./net/TerminalsPanel";
import { VenuePanel } from "./net/VenuePanel";
import { WaitingPanel } from "./net/WaitingPanel";

/**
 * «Сеть» — экран мастера для VR-части игры: состояние Моста, «ждём мастера», флэтлайн, узлы, нетраннеры, терминалы, тревоги
 * аудитора, запросы к Сети, заготовки. Браузер к Мосту не подключается: всё идёт через коллектор, он держит одно соединение и
 * отдаёт копию. Пока Моста нет, данных Сети не показываем — только шапка «Мост недоступен» и настройки коллектора (площадка, СБ),
 * которые от Моста не зависят.
 */
export function NetScreen() {
  const { data: state, error, reload } = useApiData<NetState>("/api/net/state", { pollMs: POLL_LIVE_MS });
  const { data: flags, reload: reloadFlags } = useApiData<NetRunnerFlagItem[]>("/api/net/runners", { pollMs: POLL_LIVE_MS });
  const refresh = () => {
    reload();
    reloadFlags();
  };
  const live = state?.bridge === "connected";

  return (
    <div className="screen-grid">
      {error && <ErrorNote>{error}</ErrorNote>}
      {state && <BridgeHeader state={state} reload={refresh} />}
      <FlatlinePanel flags={flags ?? []} reload={refresh} />
      {state && live && (
        <>
          <WaitingPanel state={state} reload={refresh} />
          <AlertsPanel state={state} reload={refresh} />
          <NodesPanel state={state} reload={refresh} />
          <SessionsPanel state={state} />
          <TerminalsPanel state={state} />
          <QueryPanel state={state} reload={refresh} />
          <TemplatesPanel state={state} reload={refresh} />
        </>
      )}
      <SecPanel />
      <VenuePanel state={live ? state : null} />
    </div>
  );
}
