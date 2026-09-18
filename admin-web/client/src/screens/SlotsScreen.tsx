import { useState } from "react";
import { api } from "../api/client";
import type { SlotRegistryItem } from "../api/types";
import { useApiData } from "../api/useApiData";
import { AppButton, AppDialog, AppInput, AppSelect, Badge, EmptyState, ErrorNote, Panel } from "../design/components";
import { DataTable, type Column } from "../design/DataTable";
import { shortKey } from "../format";

type Filter = "all" | "open" | "exhausted";
const POLL_MS = 8000;

export function SlotsScreen() {
  const { data: slots, error, reload } = useApiData<SlotRegistryItem[]>("/api/slots", { pollMs: POLL_MS });
  const [filter, setFilter] = useState<Filter>("all");
  const [revoking, setRevoking] = useState<{ slotRef: string; claimantKeyB64: string } | null>(null);
  const [revokeReason, setRevokeReason] = useState("");

  async function confirmRevoke() {
    if (!revoking) return;
    await api.post(`/api/slots/${encodeURIComponent(revoking.slotRef)}/revoke`, { claimantKeyB64: revoking.claimantKeyB64, reason: revokeReason });
    setRevoking(null);
    setRevokeReason("");
    reload();
  }
  async function restore(slotRef: string) {
    await api.post(`/api/slots/${encodeURIComponent(slotRef)}/restore`, {});
    reload();
  }

  const filtered = (slots ?? []).filter((s) => {
    if (filter === "open") return s.copiesClaimed < s.copiesTotal;
    if (filter === "exhausted") return s.copiesClaimed >= s.copiesTotal;
    return true;
  });

  const columns: Column<SlotRegistryItem>[] = [
    { key: "slotRef", label: "Слот", render: (s) => s.slotRef, sortValue: (s) => s.slotRef },
    { key: "container", label: "Узел", render: (s) => s.containerName, sortValue: (s) => s.containerName },
    { key: "title", label: "Содержимое", render: (s) => s.title, sortValue: (s) => s.title },
    { key: "type", label: "Тип", render: (s) => s.type, sortValue: (s) => s.type },
    { key: "tier", label: "Тир", render: (s) => s.tier, sortValue: (s) => s.tier },
    {
      key: "copies",
      label: "Занято/всего",
      render: (s) => (
        <Badge tone={s.copiesClaimed >= s.copiesTotal ? "danger" : "ok"}>
          {s.copiesClaimed}/{s.copiesTotal}
        </Badge>
      ),
      sortValue: (s) => s.copiesClaimed / s.copiesTotal,
    },
    {
      key: "claimants",
      label: "Кто забрал",
      render: (s) => (
        <div className="claimants-cell">
          {s.claimants.map((c) => (
            <div key={c.claimantKeyB64} className="claimant-row">
              <span>{shortKey(c.claimantKeyB64)}</span>
              <AppButton variant="danger" onClick={() => setRevoking({ slotRef: s.slotRef, claimantKeyB64: c.claimantKeyB64 })}>
                аннулировать
              </AppButton>
            </div>
          ))}
          {s.copiesClaimed > 0 && <AppButton onClick={() => restore(s.slotRef)}>вернуть в оборот</AppButton>}
        </div>
      ),
    },
  ];

  return (
    <>
      <Panel
        title="Реестр тиражей"
        action={
          <AppSelect value={filter} onChange={(e) => setFilter(e.target.value as Filter)}>
            <option value="all">все</option>
            <option value="open">в обороте</option>
            <option value="exhausted">исчерпаны</option>
          </AppSelect>
        }
      >
        {error && <ErrorNote>{error}</ErrorNote>}
        {slots === null ? (
          <EmptyState>загрузка…</EmptyState>
        ) : filtered.length === 0 ? (
          <EmptyState>нет тиражных слотов</EmptyState>
        ) : (
          <DataTable columns={columns} rows={filtered} rowKey={(s) => s.slotRef} />
        )}
      </Panel>
      {revoking && (
        <AppDialog
          title="Аннулировать заявку"
          body={`Слот ${revoking.slotRef}, заявитель ${shortKey(revoking.claimantKeyB64)}. Слот вернётся в оборот для этого игрока.`}
          confirmText="Аннулировать"
          confirmVariant="danger"
          confirmDisabled={!revokeReason.trim()}
          onConfirm={confirmRevoke}
          onCancel={() => {
            setRevoking(null);
            setRevokeReason("");
          }}
        >
          <AppInput autoFocus placeholder="основание (обязательно)" value={revokeReason} onChange={(e) => setRevokeReason(e.target.value)} />
        </AppDialog>
      )}
    </>
  );
}
