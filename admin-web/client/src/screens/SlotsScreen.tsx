import { useState } from "react";
import { api } from "../api/client";
import type { SlotRegistryItem } from "../api/types";
import { useApiData } from "../api/useApiData";
import { useAsyncAction } from "../api/useAsyncAction";
import { AsyncPanel } from "../design/AsyncPanel";
import { AppButton, AppDialog, AppInput, AppSelect, Badge, Panel } from "../design/components";
import { DataTable, type Column } from "../design/DataTable";
import { shortKey } from "../format";

type Filter = "all" | "open" | "exhausted";

export function SlotsScreen() {
  const { data: slots, error, reload } = useApiData<SlotRegistryItem[]>("/api/slots");
  const [filter, setFilter] = useState<Filter>("all");
  const [revoking, setRevoking] = useState<{ slotRef: string; claimantKeyB64: string } | null>(null);
  const [revokeReason, setRevokeReason] = useState("");
  const revokeAction = useAsyncAction({ fallbackError: "не удалось аннулировать заявку" });
  const restoreAction = useAsyncAction({ fallbackError: "не удалось вернуть слот в оборот" });

  async function confirmRevoke() {
    if (!revoking) return;
    const res = await revokeAction.run(() =>
      api.post(`/api/slots/${encodeURIComponent(revoking.slotRef)}/revoke`, { claimantKeyB64: revoking.claimantKeyB64, reason: revokeReason }),
    );
    if (res.ok) {
      setRevoking(null);
      setRevokeReason("");
      reload();
    }
  }
  async function restore(slotRef: string) {
    const res = await restoreAction.run(() => api.post(`/api/slots/${encodeURIComponent(slotRef)}/restore`, {}));
    if (res.ok) reload();
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
          {s.copiesClaimed > 0 && (
            <AppButton onClick={() => restore(s.slotRef)} disabled={restoreAction.busy}>
              вернуть в оборот
            </AppButton>
          )}
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
        {restoreAction.error && <div className="login-error">{restoreAction.error}</div>}
        <AsyncPanel data={slots} error={error} isEmpty={() => filtered.length === 0} emptyLabel="нет тиражных слотов">
          {() => <DataTable columns={columns} rows={filtered} rowKey={(s) => s.slotRef} />}
        </AsyncPanel>
      </Panel>
      {revoking && (
        <AppDialog
          title="Аннулировать заявку"
          body={`Слот ${revoking.slotRef}, заявитель ${shortKey(revoking.claimantKeyB64)}. Слот вернётся в оборот для этого игрока.`}
          confirmText={revokeAction.busy ? "Аннулирую…" : "Аннулировать"}
          confirmVariant="danger"
          confirmDisabled={!revokeReason.trim() || revokeAction.busy}
          onConfirm={confirmRevoke}
          onCancel={() => {
            setRevoking(null);
            setRevokeReason("");
          }}
        >
          <AppInput autoFocus placeholder="основание (обязательно)" value={revokeReason} onChange={(e) => setRevokeReason(e.target.value)} />
          {revokeAction.error && <div className="login-error">{revokeAction.error}</div>}
        </AppDialog>
      )}
    </>
  );
}
