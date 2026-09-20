import type { Economy } from "../api/types";
import { useApiData } from "../api/useApiData";
import { AsyncPanel } from "../design/AsyncPanel";
import { LineChart, ShareBar } from "../design/charts";
import { Panel, StatTile } from "../design/components";
import { DataTable, type Column } from "../design/DataTable";
import { formatNumber } from "../format";
import { navigate } from "../router";

/** Экономика игры: сколько эдди в обороте, как менялось, откуда берётся и как распределено — чтобы вовремя заметить инфляцию или перекос. */
export function EconomyScreen() {
  const { data: e, error } = useApiData<Economy>("/api/economy");

  return (
    <div className="screen-grid">
      <AsyncPanel data={e} error={error}>
        {(d) => {
          const maxSource = Math.max(1, ...d.sources.map((s) => Math.abs(s.total)));
          const columns: Column<Economy["top"][number]>[] = [
            { key: "callsign", label: "Игрок", render: (p) => p.callsign || "—", sortValue: (p) => p.callsign },
            { key: "faction", label: "Фракция", render: (p) => p.faction || "—", sortValue: (p) => p.faction },
            { key: "balance", label: "Эдди", render: (p) => formatNumber(p.balance), sortValue: (p) => p.balance },
          ];
          return (
            <>
              <div className="stat-row">
                <StatTile label="Эдди в обороте" value={formatNumber(d.totalSupply)} tone="accent" />
                <StatTile label="Медианный баланс" value={formatNumber(d.distribution.median)} />
                <StatTile label="Топ-10% начинается с" value={formatNumber(d.distribution.p90)} />
                <StatTile label="Неравенство (Джини)" value={d.distribution.gini.toFixed(2)} />
                <StatTile label="В минусе" value={d.distribution.negative} tone={d.distribution.negative > 0 ? "danger" : undefined} />
              </div>

              <Panel title="Эдди в обороте по времени">
                <LineChart points={d.series.map((p) => ({ t: p.t, v: p.supply }))} />
                <p className="hint-text">
                  Накопленная сумма всех изменений балансов по часам сервера. Переводы между игроками её не меняют — растёт она только от эмиссии (взломы, шарды, правки мастера).
                </p>
              </Panel>

              <div className="two-col">
                <Panel title="Откуда берутся деньги">
                  {d.sources.length === 0 ? (
                    <p className="hint-text">пока ничего не начислялось</p>
                  ) : (
                    d.sources.map((s) => (
                      <div key={s.reason} className="slot-row">
                        <span>{s.label}</span>
                        <span>
                          <span className="mono">{s.total > 0 ? "+" : ""}{formatNumber(s.total)}</span> <ShareBar value={s.total} max={maxSource} />
                        </span>
                      </div>
                    ))
                  )}
                  <p className="hint-text">Оборот переводов между игроками: {formatNumber(d.transferVolume)} €$ — деньги лишь переходят из рук в руки.</p>
                </Panel>

                <Panel title="Самые богатые">
                  <DataTable columns={columns} rows={d.top} rowKey={(p) => p.publicKeyB64} onRowClick={(p) => navigate("players", p.publicKeyB64)} />
                </Panel>
              </div>
            </>
          );
        }}
      </AsyncPanel>
    </div>
  );
}
