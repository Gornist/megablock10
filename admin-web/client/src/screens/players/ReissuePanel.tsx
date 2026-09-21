import { useState } from "react";
import type { CharacterSnapshot, ProvisionQr } from "../../api/types";
import { AppButton } from "../../design/components";
import { ProvisionIssuer } from "../master/ProvisionIssuer";
import { QrPanel } from "../master/common";

/**
 * «Выдать заново»: форма с сохранёнными параметрами игрока (позывной, фракция, баланс, RAM) — поправить при необходимости и выдать:
 * два клика (кнопка на карточке → «Выдать»). Прежний код гасится, прежний ключ пометится «заменён», когда новый телефон применит QR.
 */
export function ReissuePanel({ snapshot, onClose }: { snapshot: CharacterSnapshot; onClose: () => void }) {
  const [result, setResult] = useState<ProvisionQr | null>(null);
  return (
    <>
      <ProvisionIssuer
        title="Выдать персонажа заново"
        action={<AppButton onClick={onClose}>закрыть</AppButton>}
        intro="Новый телефон получит эти параметры. Предметы не возвращаются — только позывной, фракция, баланс и RAM. Прежний QR этого игрока гасится; прежняя сессия перестанет считаться в сводках, когда новый телефон применит код."
        initial={{ callsign: snapshot.callsign, faction: snapshot.faction, balance: String(Math.max(0, snapshot.balance)), ram: String(snapshot.ramCapacity) }}
        endpoint={`/api/players/${encodeURIComponent(snapshot.publicKeyB64)}/reissue`}
        submitLabel="Выдать и показать QR"
        submitAgainLabel="Выдать ещё один код (прежний погаснет)"
        balanceLabel="Баланс, эдди"
        extraRam={snapshot.ramCapacity}
        onResult={setResult}
      />
      {result && <QrPanel result={result} caption={`${result.item.callsign} · ${result.item.balance} €$ · заменяет прежнюю сессию`} />}
    </>
  );
}
