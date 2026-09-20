import { useState } from "react";
import { api } from "../api/client";
import type { CharacterSnapshot, EventsResponse } from "../api/types";
import { useApiData } from "../api/useApiData";
import { useAsyncAction } from "../api/useAsyncAction";
import { AppButton, AppInput, AppSelect, Badge, EmptyState, ErrorNote, HexRow, Panel, StatTile } from "../design/components";
import { ChangeLine } from "../design/ChangeLine";
import { useMeta } from "../api/useMeta";
import { useWatch } from "../api/useWatch";
import { fromDatetimeLocal, shortKey, toDatetimeLocal } from "../format";
import { navigate } from "../router";


const OVERRIDE_FIELDS = ["balance", "ramCapacity", "callsign", "faction"];

export function PlayerDetailScreen({ publicKeyB64 }: { publicKeyB64: string }) {
  const [refreshTick, setRefreshTick] = useState(0);
  // «Состояние на момент T» — для разбора споров: что было у игрока тогда, а не сейчас.
  const [asOf, setAsOf] = useState("");
  const [nowLocal] = useState(() => toDatetimeLocal(Date.now()));
  const asOfMs = asOf ? fromDatetimeLocal(asOf) : null;
  const { data: snapshot, error: snapshotError } = useApiData<CharacterSnapshot>(
    `/api/players/${encodeURIComponent(publicKeyB64)}?t=${refreshTick}${asOfMs ? `&until=${asOfMs}` : ""}`,
    { pollMs: false },
  );
  const meta = useMeta();
  const watch = useWatch();
  const watched = watch.byKey.get(publicKeyB64);
  const [note, setNote] = useState("");

  const [reasonFilter, setReasonFilter] = useState("");
  const [sourceFilter, setSourceFilter] = useState("");
  const [page, setPage] = useState(0);

  // refreshTick в запросе — чтобы после правки мастера история перезагрузилась (сервер параметр t игнорирует).
  const historyQuery = new URLSearchParams({ page: String(page), pageSize: "50", t: String(refreshTick) });
  if (reasonFilter) historyQuery.set("reason", reasonFilter);
  if (sourceFilter) historyQuery.set("source", sourceFilter);
  const { data: historyData, error: historyError } = useApiData<EventsResponse>(
    `/api/players/${encodeURIComponent(publicKeyB64)}/history?${historyQuery}`,
    { pollMs: false },
  );
  const history = historyData?.records ?? null;
  const historyTotal = historyData?.total ?? 0;

  if (snapshotError) return <ErrorNote>{snapshotError}</ErrorNote>;
  if (!snapshot) return <EmptyState>загрузка…</EmptyState>;

  const breachTotals = Object.values(snapshot.counters.breaches).reduce(
    (acc, b) => ({ success: acc.success + b.success, partial: acc.partial + b.partial, fail: acc.fail + b.fail }),
    { success: 0, partial: 0, fail: 0 },
  );
  const blockedTotal = Object.values(snapshot.counters.breachesBlocked).reduce((a, b) => a + b, 0);

  return (
    <div className="screen-grid">
      <div className="panel-header-row filter-row">
        <AppButton onClick={() => navigate("players")}>← к списку</AppButton>
        <AppButton onClick={() => navigate("events", "player", publicKeyB64)}>все события игрока →</AppButton>
        <AppButton variant={watched ? "primary" : "default"} onClick={() => (watched ? void watch.remove(publicKeyB64) : void watch.set(publicKeyB64, note))}>
          {watched ? "★ под наблюдением" : "☆ следить"}
        </AppButton>
        {watched ? (
          <AppInput
            placeholder="пометка (Enter — сохранить)"
            defaultValue={watched.note}
            key={watched.note}
            onKeyDown={(e) => {
              if (e.key === "Enter") void watch.set(publicKeyB64, e.currentTarget.value);
            }}
          />
        ) : (
          <AppInput placeholder="пометка для наблюдения" value={note} onChange={(e) => setNote(e.target.value)} />
        )}
        <AppInput type="datetime-local" title="Состояние на момент времени" value={asOf} max={nowLocal} onChange={(e) => setAsOf(e.target.value)} />
      </div>

      {asOfMs && (
        <div className="asof-banner">
          Состояние на {new Date(asOfMs).toLocaleString("ru-RU")} — история, не текущая картина. Правка отключена.{" "}
          <button type="button" className="change-toggle" onClick={() => setAsOf("")}>
            вернуться к текущему
          </button>
        </div>
      )}

      <div className="stat-row">
        <StatTile label="Позывной" value={snapshot.callsign || "—"} />
        <StatTile label="Фракция" value={snapshot.faction || "—"} />
        <StatTile label="RAM" value={snapshot.ramCapacity} />
        <StatTile label="Эдди" value={snapshot.balance} tone="accent" />
      </div>

      <Panel title="Счётчики">
        <div className="counters-grid">
          <span>
            Взломы (успех / частично / провал): <span className="mono">{breachTotals.success}/{breachTotals.partial}/{breachTotals.fail}</span>
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
            Сигналы СБ (отправлено / подавлено): <span className="mono">{snapshot.counters.alertsSent}/{snapshot.counters.alertsSuppressed}</span>
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

      {!asOfMs && <OverridePanel publicKeyB64={publicKeyB64} onDone={() => setRefreshTick((t) => t + 1)} />}

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
              {(meta?.reasons ?? []).map((r) => (
                <option key={r.code} value={r.code}>
                  {r.label}
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
              <ChangeLine key={r.id} row={r} showSubject={false} time="happened" />
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
