import { useState } from "react";
import { api } from "../../api/client";
import type { FactionRow, ProvisionItem, ProvisionQr, ProvisionsResponse } from "../../api/types";
import { useApiData } from "../../api/useApiData";
import { POLL_RELAXED_MS } from "../../api/pollIntervals";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AsyncPanel } from "../../design/AsyncPanel";
import { Badge, Panel } from "../../design/components";
import { DataTable, type Column } from "../../design/DataTable";
import { formatAgo } from "../../format";
import { QrPanel } from "./common";
import { ProvisionIssuer } from "./ProvisionIssuer";
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

/** Форма «Персонаж»: выдача нового персонажа QR-кодом первого запуска (docs/provisioning-qr.md). Последние фракция/баланс/RAM запоминаются — выдача пачки в 2 клика. */
export function ProvisionForm() {
  const last = loadLast();
  const [result, setResult] = useState<ProvisionQr | null>(null);
  const { error: showError, run } = useAsyncAction({ fallbackError: "не удалось показать код" });
  const { data, error: listError, reload } = useApiData<ProvisionsResponse>("/api/provisions", { pollMs: POLL_RELAXED_MS });
  const { data: factions } = useApiData<FactionRow[]>("/api/factions", { pollMs: false });

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
      <ProvisionIssuer
        title="Новый персонаж"
        intro="Игрок сканирует один QR на первом запуске: приложение настроится и создаст персонажа. Код работает один раз — копия на втором телефоне не примется."
        initial={{ callsign: "", ...last }}
        endpoint="/api/provisions"
        submitLabel="Выдать и показать QR"
        factions={(factions ?? []).map((f) => f.faction).filter(Boolean)}
        autoFocus
        keepAfterIssue={{ callsign: "" }} // следующий игрок: фракция, баланс и RAM остаются
        onResult={(r) => {
          setResult(r);
          reload();
        }}
        onIssued={({ faction, balance, ram }) => {
          try {
            localStorage.setItem(LAST_KEY, JSON.stringify({ faction, balance, ram }));
          } catch {
            // запоминание — удобство, не необходимость
          }
        }}
      />
      {showError && <div className="login-error">{showError}</div>}

      {result && <QrPanel result={result} caption={`${result.item.callsign}${result.item.faction ? ` · ${result.item.faction}` : ""} · ${result.item.balance} €$`} />}

      <Panel title={`Выданные коды${data ? ` (${data.items.length})` : ""}`}>
        <AsyncPanel data={data} error={listError} isEmpty={(d) => d.items.length === 0} emptyLabel="кодов пока не выдавали">
          {(d) => <DataTable columns={columns} rows={d.items} rowKey={(p) => p.id} />}
        </AsyncPanel>
      </Panel>
    </>
  );
}
