import { useState } from "react";
import type { CharacterSnapshot } from "../api/types";
import { useApiData } from "../api/useApiData";
import { AppButton, AppInput, EmptyState, ErrorNote, StatTile } from "../design/components";
import { fromDatetimeLocal, toDatetimeLocal } from "../format";
import { navigate } from "../router";
import { CountersPanel } from "./player/CountersPanel";
import { HistoryPanel } from "./player/HistoryPanel";
import { ItemsPanels } from "./player/ItemsPanels";
import { OverridePanel } from "./player/OverridePanel";
import { PlayerBanners } from "./player/PlayerBanners";
import { WatchControls } from "./player/WatchControls";
import { ReissuePanel } from "./players/ReissuePanel";

/** Карточка игрока: состояние (в том числе «на момент T»), счётчики, предметы, ручная правка, повторная выдача и история. Панели — в screens/player/. */
export function PlayerDetailScreen({ publicKeyB64 }: { publicKeyB64: string }) {
  const [refreshTick, setRefreshTick] = useState(0);
  // «Состояние на момент T» — для разбора споров: что было у игрока тогда, а не сейчас.
  const [asOf, setAsOf] = useState("");
  const [nowLocal] = useState(() => toDatetimeLocal(Date.now()));
  const asOfMs = asOf ? fromDatetimeLocal(asOf) : null;
  const { data: snapshot, error } = useApiData<CharacterSnapshot>(
    `/api/players/${encodeURIComponent(publicKeyB64)}?t=${refreshTick}${asOfMs ? `&until=${asOfMs}` : ""}`,
    { pollMs: false },
  );
  const [reissueOpen, setReissueOpen] = useState(false);

  if (error) return <ErrorNote>{error}</ErrorNote>;
  if (!snapshot) return <EmptyState>загрузка…</EmptyState>;

  return (
    <div className="screen-grid">
      <div className="panel-header-row filter-row">
        <AppButton onClick={() => navigate("players")}>← к списку</AppButton>
        <AppButton onClick={() => navigate("events", "player", publicKeyB64)}>все события игрока →</AppButton>
        <WatchControls publicKeyB64={publicKeyB64} />
        <AppInput type="datetime-local" title="Состояние на момент времени" value={asOf} max={nowLocal} onChange={(e) => setAsOf(e.target.value)} />
        {!asOfMs && (
          <AppButton variant={snapshot.sessionResetAt ? "primary" : "default"} onClick={() => setReissueOpen((v) => !v)}>
            Выдать заново
          </AppButton>
        )}
      </div>

      {asOfMs && (
        <div className="asof-banner">
          Состояние на {new Date(asOfMs).toLocaleString("ru-RU")} — история, не текущая картина. Правка отключена.{" "}
          <button type="button" className="change-toggle" onClick={() => setAsOf("")}>
            вернуться к текущему
          </button>
        </div>
      )}
      <PlayerBanners snapshot={snapshot} />
      {reissueOpen && !asOfMs && <ReissuePanel snapshot={snapshot} onClose={() => setReissueOpen(false)} />}

      <div className="stat-row">
        <StatTile label="Позывной" value={snapshot.callsign || "—"} />
        <StatTile label="Фракция" value={snapshot.faction || "—"} />
        <StatTile label="RAM" value={snapshot.ramCapacity} />
        <StatTile label="Эдди" value={snapshot.balance} tone="accent" />
      </div>

      <CountersPanel snapshot={snapshot} />
      <ItemsPanels snapshot={snapshot} />
      {!asOfMs && <OverridePanel publicKeyB64={publicKeyB64} onDone={() => setRefreshTick((t) => t + 1)} />}
      <HistoryPanel publicKeyB64={publicKeyB64} refreshTick={refreshTick} />
    </div>
  );
}
