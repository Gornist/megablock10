import { useState } from "react";
import { api } from "../../api/client";
import type { NetDoc, NetState } from "../../api/types";
import { AsyncPanel } from "../../design/AsyncPanel";
import { AppButton, AppDialog, AppInput, AppSelect, Badge, ErrorNote, Field, Panel } from "../../design/components";
import { DataTable, type Column } from "../../design/DataTable";
import { tierLabel } from "../../format";
import { docsOf, numOf, obj, remainingLabel, text, useNetCall } from "./netUtil";

const GOAL_KINDS: { value: string; label: string }[] = [
  { value: "open", label: "открыть узел" },
  { value: "lockdown", label: "локдаун" },
  { value: "trace", label: "трейс" },
  { value: "ice", label: "ICE" },
];
const goalLabel = (k: string) => GOAL_KINDS.find((g) => g.value === k)?.label ?? k;

interface Row {
  node: NetDoc;
  cfg: Record<string, unknown>;
}

type Dialog = { kind: "goal" | "owner"; node: NetDoc } | null;

/** Узлы Сети: состояние, цель со сроком, локдаун, пауза узла и фракция-владелец (от неё зависит, кому уйдёт сигнал СБ). */
export function NodesPanel({ state, reload }: { state: NetState; reload: () => void }) {
  const { busy, error, call } = useNetCall(reload);
  const [dialog, setDialog] = useState<Dialog>(null);
  const [goalKind, setGoalKind] = useState("open");
  const [goalValue, setGoalValue] = useState("");
  const [goalMin, setGoalMin] = useState("10");
  const [owner, setOwner] = useState("");

  const cfg = new Map(docsOf(state, "node_cfg").map((d) => [d.id, d.data]));
  const rows: Row[] = docsOf(state, "node").map((n) => ({ node: n, cfg: obj(cfg.get(n.id)) }));

  const columns: Column<Row>[] = [
    { key: "node", label: "Узел", render: (r) => (<><span className="mono">{r.node.id}</span> {text(r.node.data.title)}</>), sortValue: (r) => r.node.id },
    { key: "tier", label: "Тир", render: (r) => tierLabel(text(r.node.data.tier)), sortValue: (r) => text(r.node.data.tier) },
    { key: "eddies", label: "Эдди", render: (r) => numOf(r.node.data.eddies) ?? "—", sortValue: (r) => numOf(r.node.data.eddies) ?? -1 },
    {
      key: "state",
      label: "Состояние",
      render: (r) => {
        const lock = remainingLabel(numOf(r.node.data.lockdown_until), state.serverNow);
        const locked = (numOf(r.node.data.lockdown_until) ?? 0) > state.serverNow;
        return (
          <span className="filter-row filter-wrap">
            {r.node.data.tutorial === true && <Badge tone="info">учебный</Badge>}
            {r.cfg.paused === true && <Badge tone="danger">пауза</Badge>}
            {locked && <Badge tone="warn">локдаун {lock}</Badge>}
            {r.cfg.paused !== true && !locked && <Badge tone="ok">открыт</Badge>}
          </span>
        );
      },
    },
    {
      key: "goal",
      label: "Цель",
      render: (r) => {
        const g = obj(r.cfg.goal);
        if (!text(g.kind)) return "—";
        const left = remainingLabel(numOf(g.deadline), state.serverNow);
        return (
          <span>
            {goalLabel(text(g.kind))}
            {numOf(g.value) !== null ? ` ${numOf(g.value)}` : ""}
            {g.done === true ? " · выполнена" : left ? ` · ${left}` : ""}
          </span>
        );
      },
    },
    { key: "owner", label: "Владелец", render: (r) => text(r.node.data.owner_faction) || "—", sortValue: (r) => text(r.node.data.owner_faction) },
    {
      key: "act",
      label: "",
      render: (r) => (
        <span className="filter-row filter-wrap">
          <AppButton disabled={busy} onClick={() => setDialog({ kind: "goal", node: r.node })}>цель</AppButton>
          {text(obj(r.cfg.goal).kind) && (
            <AppButton disabled={busy} onClick={() => void call(() => api.post("/api/net/goal/clear", { node: r.node.id }))}>снять цель</AppButton>
          )}
          <AppButton disabled={busy} onClick={() => void call(() => api.post("/api/net/pause", { on: r.cfg.paused !== true, node: r.node.id }))}>
            {r.cfg.paused === true ? "снять паузу" : "пауза"}
          </AppButton>
          <AppButton
            disabled={busy}
            onClick={() => {
              setOwner(text(r.node.data.owner_faction));
              setDialog({ kind: "owner", node: r.node });
            }}
          >
            владелец
          </AppButton>
        </span>
      ),
    },
  ];

  const minutes = Number(goalMin);
  const value = goalValue.trim() === "" ? undefined : Number(goalValue);
  const goalOk = Number.isFinite(minutes) && minutes >= 1 && minutes <= 1440 && (value === undefined || Number.isFinite(value));

  return (
    <Panel title={`Узлы Сети (${rows.length})`}>
      {error && <ErrorNote>{error}</ErrorNote>}
      <AsyncPanel data={rows} isEmpty={(d) => d.length === 0} emptyLabel="узлов в Мосте пока нет">
        {(d) => <DataTable columns={columns} rows={d} rowKey={(r) => r.node.id} />}
      </AsyncPanel>
      {dialog?.kind === "goal" && (
        <AppDialog
          title={`Цель узла ${dialog.node.id}`}
          body="Цель со сроком: к дедлайну Мост проверит исход. Срок отсчитывается от нажатия."
          confirmText="Поставить"
          confirmDisabled={!goalOk}
          onCancel={() => setDialog(null)}
          onConfirm={() => {
            const node = dialog.node.id;
            setDialog(null);
            void call(() => api.post("/api/net/goal", { node, kind: goalKind, ...(value !== undefined ? { value } : {}), in_s: Math.round(minutes * 60) }));
          }}
        >
          <Field label="что сделать">
            <AppSelect value={goalKind} onChange={(e) => setGoalKind(e.target.value)} aria-label="вид цели">
              {GOAL_KINDS.map((g) => (
                <option key={g.value} value={g.value}>{g.label}</option>
              ))}
            </AppSelect>
          </Field>
          <Field label="значение (по желанию)">
            <AppInput inputMode="decimal" value={goalValue} onChange={(e) => setGoalValue(e.target.value)} aria-label="значение цели" />
          </Field>
          <Field label="срок, минут">
            <AppInput inputMode="numeric" value={goalMin} onChange={(e) => setGoalMin(e.target.value)} aria-label="срок в минутах" />
          </Field>
        </AppDialog>
      )}
      {dialog?.kind === "owner" && (
        <AppDialog
          title={`Владелец узла ${dialog.node.id}`}
          body="Фракция, чьим телефонам Мост шлёт сигнал СБ, когда нетраннер в этом узле дошёл до трейса. Пусто — владельца нет (берётся фракция СБ по умолчанию)."
          confirmText="Сохранить"
          onCancel={() => setDialog(null)}
          onConfirm={() => {
            const node = dialog.node.id;
            setDialog(null);
            void call(() => api.put(`/api/net/nodes/${encodeURIComponent(node)}/owner`, { faction: owner.trim() || null }));
          }}
        >
          <AppInput value={owner} onChange={(e) => setOwner(e.target.value)} placeholder="название фракции" aria-label="фракция-владелец" maxLength={64} />
        </AppDialog>
      )}
    </Panel>
  );
}
