import { useEffect, useState } from "react";
import { api, ApiError } from "../api/client";
import type { CharacterSnapshot, ChangeRow } from "../api/types";
import { useApiData } from "../api/useApiData";
import { useAsyncAction } from "../api/useAsyncAction";
import { AppButton, AppInput, AppSelect, Badge, EmptyState, ErrorNote, HexRow, Panel, StatTile } from "../design/components";
import { formatTime, shortKey } from "../format";
import { navigate } from "../router";

const REASONS = [
  "CHARACTER_CREATED",
  "BREACH_ATTEMPT",
  "BREACH_BLOCKED",
  "BREACH_LOOT",
  "BREACH_EDDIES",
  "SHARD_SCAN",
  "SHARD_DECRYPT",
  "TRANSFER_OUT",
  "TRANSFER_IN",
  "RAM_UPGRADE",
  "ALERT_SENT",
  "ALERT_SUPPRESSED",
  "MASTER_OVERRIDE",
  "CHARACTER_RESET",
];

const OVERRIDE_FIELDS = ["balance", "ramCapacity", "callsign", "faction"];

export function PlayerDetailScreen({ publicKeyB64 }: { publicKeyB64: string }) {
  const [refreshTick, setRefreshTick] = useState(0);
  const { data: snapshot, error: snapshotError } = useApiData<CharacterSnapshot>(
    `/api/players/${encodeURIComponent(publicKeyB64)}?t=${refreshTick}`,
    { pollMs: false },
  );

  const [history, setHistory] = useState<ChangeRow[] | null>(null);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [historyTotal, setHistoryTotal] = useState(0);
  const [reasonFilter, setReasonFilter] = useState("");
  const [sourceFilter, setSourceFilter] = useState("");
  const [page, setPage] = useState(0);

  useEffect(() => {
    let cancelled = false;
    const q = new URLSearchParams({ page: String(page), pageSize: "50" });
    if (reasonFilter) q.set("reason", reasonFilter);
    if (sourceFilter) q.set("source", sourceFilter);
    api
      .get<{ total: number; records: ChangeRow[] }>(`/api/players/${encodeURIComponent(publicKeyB64)}/history?${q}`)
      .then((r) => {
        if (cancelled) return;
        setHistoryTotal(r.total);
        setHistory(r.records);
        setHistoryError(null);
      })
      .catch((err) => {
        if (cancelled) return;
        setHistoryError(err instanceof ApiError ? err.message : "не удалось связаться с сервером");
      });
    return () => {
      cancelled = true;
    };
  }, [publicKeyB64, reasonFilter, sourceFilter, page, refreshTick]);

  if (snapshotError) return <ErrorNote>{snapshotError}</ErrorNote>;
  if (!snapshot) return <EmptyState>загрузка…</EmptyState>;

  const breachTotals = Object.values(snapshot.counters.breaches).reduce(
    (acc, b) => ({ success: acc.success + b.success, partial: acc.partial + b.partial, fail: acc.fail + b.fail }),
    { success: 0, partial: 0, fail: 0 },
  );
  const blockedTotal = Object.values(snapshot.counters.breachesBlocked).reduce((a, b) => a + b, 0);

  return (
    <div className="screen-grid">
      <div className="panel-header-row">
        <AppButton onClick={() => navigate("players")}>← к списку</AppButton>
      </div>

      <div className="stat-row">
        <StatTile label="Позывной" value={snapshot.callsign || "—"} />
        <StatTile label="Фракция" value={snapshot.faction || "—"} />
        <StatTile label="RAM" value={snapshot.ramCapacity} />
        <StatTile label="Эдди" value={snapshot.balance} tone="accent" />
      </div>

      <Panel title="Счётчики">
        <div className="counters-grid">
          <span>
            Взломы у/ч/п: <span className="mono">{breachTotals.success}/{breachTotals.partial}/{breachTotals.fail}</span>
          </span>
          <span>
            Заблокировано попыток: <span className="mono">{blockedTotal}</span>
            {blockedTotal > 0 && (
              <span className="hint-text">
                {" "}
                ({Object.entries(snapshot.counters.breachesBlocked).map(([reason, n]) => `${reason}: ${n}`).join(", ")})
              </span>
            )}
          </span>
          <span>
            Слотов забрано: <span className="mono">{snapshot.counters.slotsClaimed}</span>
          </span>
          <span>
            Сигналы СБ отпр/подавл: <span className="mono">{snapshot.counters.alertsSent}/{snapshot.counters.alertsSuppressed}</span>
          </span>
        </div>
      </Panel>

      <Panel title={`Демоны (${snapshot.daemons.length})`}>
        {snapshot.daemons.length === 0 ? (
          <EmptyState>нет</EmptyState>
        ) : (
          snapshot.daemons.map((d) => (
            <HexRow key={d.daemonId}>
              {d.name} <Badge>{d.tier}</Badge> вес {d.weight} · {d.sourceRef ?? "—"}
            </HexRow>
          ))
        )}
      </Panel>

      <Panel title={`Шарды (${snapshot.shards.length})`}>
        {snapshot.shards.length === 0 ? (
          <EmptyState>нет</EmptyState>
        ) : (
          snapshot.shards.map((s) => (
            <HexRow key={s.shardId}>
              {s.title} <Badge>{s.tier}</Badge> <Badge tone={s.decrypted ? "ok" : "neutral"}>{s.decrypted ? "расшифрован" : "зашифрован"}</Badge> ·{" "}
              {s.sourceRef ?? "—"}
            </HexRow>
          ))
        )}
      </Panel>

      <OverridePanel publicKeyB64={publicKeyB64} onDone={() => setRefreshTick((t) => t + 1)} />

      <Panel
        title={`История (${historyTotal})`}
        action={
          <div className="filter-row">
            <AppSelect
              value={reasonFilter}
              onChange={(e) => {
                setReasonFilter(e.target.value);
                setPage(0);
              }}
            >
              <option value="">все причины</option>
              {REASONS.map((r) => (
                <option key={r} value={r}>
                  {r}
                </option>
              ))}
            </AppSelect>
            <AppInput
              placeholder="поиск по источнику"
              value={sourceFilter}
              onChange={(e) => {
                setSourceFilter(e.target.value);
                setPage(0);
              }}
            />
          </div>
        }
      >
        {historyError && <ErrorNote>{historyError}</ErrorNote>}
        {history === null ? (
          <EmptyState>загрузка…</EmptyState>
        ) : history.length === 0 ? (
          <EmptyState>нет записей</EmptyState>
        ) : (
          <>
            {history.map((r) => (
              <HexRow key={r.id}>
                {formatTime(r.happened_at)} {r.field} {r.old_value ?? "∅"} → {r.new_value ?? "∅"} <Badge>{r.reason}</Badge>{" "}
                {r.source_ref && <span className="feed-source">{r.source_ref}</span>}
                {r.actor !== publicKeyB64 && <span className="feed-source">от {shortKey(r.actor)}</span>}
              </HexRow>
            ))}
            <div className="pager">
              <AppButton onClick={() => setPage((p) => Math.max(0, p - 1))} disabled={page === 0}>
                ← назад
              </AppButton>
              <span className="mono">стр. {page + 1}</span>
              <AppButton onClick={() => setPage((p) => p + 1)} disabled={(page + 1) * 50 >= historyTotal}>
                вперёд →
              </AppButton>
            </div>
          </>
        )}
      </Panel>
    </div>
  );
}

function OverridePanel({ publicKeyB64, onDone }: { publicKeyB64: string; onDone: () => void }) {
  const [field, setField] = useState(OVERRIDE_FIELDS[0]);
  const [value, setValue] = useState("");
  const [reason, setReason] = useState("");
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось сохранить правку" });

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const res = await run(() => api.post(`/api/players/${encodeURIComponent(publicKeyB64)}/override`, { field, newValue: value, reason }));
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
        <AppInput placeholder="новое значение" value={value} onChange={(e) => setValue(e.target.value)} required />
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
