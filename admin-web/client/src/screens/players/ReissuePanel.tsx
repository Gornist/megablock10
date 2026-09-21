import { useState } from "react";
import { api } from "../../api/client";
import type { CharacterSnapshot, ProvisionQr, ProvisionsResponse } from "../../api/types";
import { useApiData } from "../../api/useApiData";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, Panel } from "../../design/components";
import { ProvisionConfigNote } from "../master/ProvisionForm";
import { ProvisionFields, type ProvisionValues } from "../master/ProvisionFields";
import { QrPanel } from "../master/common";

/**
 * «Выдать заново»: форма с сохранёнными параметрами игрока (позывной, фракция, баланс, RAM) — поправить при необходимости и выдать:
 * два клика (кнопка на карточке → «Выдать»). Прежний код гасится, прежний ключ пометится «заменён», когда новый телефон применит QR.
 */
export function ReissuePanel({ snapshot, onClose }: { snapshot: CharacterSnapshot; onClose: () => void }) {
  const [values, setValues] = useState<ProvisionValues>({
    callsign: snapshot.callsign,
    faction: snapshot.faction,
    balance: String(Math.max(0, snapshot.balance)),
    ram: String(snapshot.ramCapacity),
  });
  const { callsign, faction, balance, ram } = values;
  const [result, setResult] = useState<ProvisionQr | null>(null);
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось выдать" });
  const { data } = useApiData<ProvisionsResponse>("/api/provisions", { pollMs: false });

  async function submit() {
    const res = await run(() =>
      api.post<ProvisionQr>(`/api/players/${encodeURIComponent(snapshot.publicKeyB64)}/reissue`, { callsign, faction, balance: Number(balance) || 0, ram: Number(ram) }),
    );
    if (res.ok) setResult(res.value);
  }

  return (
    <>
      <Panel title="Выдать персонажа заново" action={<AppButton onClick={onClose}>закрыть</AppButton>}>
        <div className="master-form">
          <p className="hint-text">
            Новый телефон получит эти параметры. Предметы не возвращаются — только позывной, фракция, баланс и RAM. Прежний QR этого игрока гасится; прежняя
            сессия перестанет считаться в сводках, когда новый телефон применит код.
          </p>
          {data && <ProvisionConfigNote config={data.config} />}
          <ProvisionFields values={values} onChange={setValues} extraRam={snapshot.ramCapacity} balanceLabel="Баланс, эдди" />
          {error && <div className="login-error">{error}</div>}
          <AppButton variant="primary" onClick={submit} disabled={busy || !callsign.trim()}>
            {busy ? "Выдаю…" : result ? "Выдать ещё один код (прежний погаснет)" : "Выдать и показать QR"}
          </AppButton>
        </div>
      </Panel>
      {result && <QrPanel result={result} caption={`${result.item.callsign} · ${result.item.balance} €$ · заменяет прежнюю сессию`} />}
    </>
  );
}
