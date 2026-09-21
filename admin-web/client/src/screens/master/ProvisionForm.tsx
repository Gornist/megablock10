import { useState } from "react";
import { api } from "../../api/client";
import type { FactionRow, ProvisionItem, ProvisionQr, ProvisionsResponse } from "../../api/types";
import { useApiData } from "../../api/useApiData";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AsyncPanel } from "../../design/AsyncPanel";
import { AppButton, Badge, Panel } from "../../design/components";
import { DataTable, type Column } from "../../design/DataTable";
import { formatAgo } from "../../format";
import { QrPanel } from "./common";
import { ProvisionFields, type ProvisionValues } from "./ProvisionFields";
import { provisionStatus, ramLabel } from "./provisionUtil";

const LAST_KEY = "mb10.provision.last";

function loadLast(): { faction: string; balance: string; ram: string } {
  try {
    const v = JSON.parse(localStorage.getItem(LAST_KEY) ?? "{}");
    return { faction: String(v.faction ?? ""), balance: String(v.balance ?? "0"), ram: String(v.ram ?? "0") };
  } catch {
    return { faction: "", balance: "0", ram: "0" };
  }
}

/** Что нужно знать мастеру про содержимое QR: адрес и код игры подставляются сервером, вводить их руками не нужно. */
export function ProvisionConfigNote({ config }: { config: ProvisionsResponse["config"] }) {
  return (
    <p className="hint-text">
      В QR подставляются: адрес сервера{" "}
      {config.url ? <span className="mono">{config.url}</span> : <b>не определён (задайте PUBLIC_URL на сервере — иначе останется адрес из сборки)</b>} и код игры{" "}
      {config.secretSet ? "(включён)" : "(на сервере не задан)"}. Код игры лежит в QR: не выкладывайте снимки и лишние распечатки.
    </p>
  );
}

/** Форма «Персонаж»: выдача нового персонажа QR-кодом первого запуска (docs/provisioning-qr.md). Последние фракция/баланс/RAM запоминаются — выдача пачки в 2 клика. */
export function ProvisionForm() {
  const last = loadLast();
  const [values, setValues] = useState<ProvisionValues>({ callsign: "", ...last });
  const { callsign, faction, balance, ram } = values;
  const [result, setResult] = useState<ProvisionQr | null>(null);
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось выдать" });
  const { data, error: listError, reload } = useApiData<ProvisionsResponse>("/api/provisions", { pollMs: 10000 });
  const { data: factions } = useApiData<FactionRow[]>("/api/factions", { pollMs: false });

  async function submit() {
    const res = await run(() => api.post<ProvisionQr>("/api/provisions", { callsign, faction, balance: Number(balance) || 0, ram: Number(ram) }));
    if (!res.ok) return;
    setResult(res.value);
    setValues((v) => ({ ...v, callsign: "" })); // следующий игрок: фракция, баланс и RAM остаются
    try {
      localStorage.setItem(LAST_KEY, JSON.stringify({ faction, balance, ram }));
    } catch {
      // запоминание — удобство, не необходимость
    }
    reload();
  }

  async function showAgain(id: string) {
    const res = await run(() => api.get<ProvisionQr>(`/api/provisions/${id}/qr`));
    if (res.ok) setResult(res.value);
  }

  const columns: Column<ProvisionItem>[] = [
    { key: "callsign", label: "Позывной", render: (p) => p.callsign, sortValue: (p) => p.callsign },
    { key: "faction", label: "Фракция", render: (p) => p.faction || "—", sortValue: (p) => p.faction },
    { key: "balance", label: "Эдди", render: (p) => p.balance, sortValue: (p) => p.balance },
    { key: "ram", label: "RAM", render: (p) => ramLabel(p.ram), sortValue: (p) => p.ram },
    {
      key: "status",
      label: "Статус",
      render: (p) => {
        const s = provisionStatus(p);
        return <Badge tone={s.tone}>{s.label}</Badge>;
      },
      sortValue: (p) => (p.boundKey ? 1 : p.void ? 2 : 0),
    },
    { key: "createdAt", label: "Выдан", render: (p) => formatAgo(p.createdAt), sortValue: (p) => p.createdAt },
    {
      key: "qr",
      label: "",
      render: (p) =>
        !p.boundKey && !p.void ? (
          <button type="button" className="change-toggle" onClick={() => void showAgain(p.id)}>
            показать QR
          </button>
        ) : null,
    },
  ];

  return (
    <>
      <Panel title="Новый персонаж">
        <div className="master-form">
          <p className="hint-text">
            Игрок сканирует один QR на первом запуске: приложение настроится и создаст персонажа. Код работает один раз — копия на втором телефоне не примется.
          </p>
          {data && <ProvisionConfigNote config={data.config} />}
          <ProvisionFields values={values} onChange={setValues} factions={(factions ?? []).map((f) => f.faction).filter(Boolean)} autoFocus />
          {error && <div className="login-error">{error}</div>}
          <AppButton variant="primary" onClick={submit} disabled={busy || !callsign.trim()}>
            {busy ? "Выдаю…" : "Выдать и показать QR"}
          </AppButton>
        </div>
      </Panel>

      {result && <QrPanel result={result} caption={`${result.item.callsign}${result.item.faction ? ` · ${result.item.faction}` : ""} · ${result.item.balance} €$`} />}

      <Panel title={`Выданные коды${data ? ` (${data.items.length})` : ""}`}>
        <AsyncPanel data={data} error={listError} isEmpty={(d) => d.items.length === 0} emptyLabel="кодов пока не выдавали">
          {(d) => <DataTable columns={columns} rows={d.items} rowKey={(p) => p.id} />}
        </AsyncPanel>
      </Panel>
    </>
  );
}
