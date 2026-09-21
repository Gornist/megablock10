import { useState, type ReactNode } from "react";
import { api } from "../../api/client";
import type { ProvisionQr, ProvisionsResponse } from "../../api/types";
import { useApiData } from "../../api/useApiData";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, Panel } from "../../design/components";
import { ProvisionConfigNote } from "./ProvisionConfigNote";
import { ProvisionFields, type ProvisionValues } from "./ProvisionFields";

/**
 * Общая форма выдачи персонажа: новый персонаж (Мастерская → «Персонаж») и «Выдать заново» на карточке игрока отличаются только
 * адресом запроса, начальными значениями и подписями. Результат (QR) отдаётся вызывающему через onResult.
 */
export function ProvisionIssuer({
  title,
  action,
  intro,
  initial,
  endpoint,
  submitLabel,
  submitAgainLabel = submitLabel,
  balanceLabel,
  extraRam,
  factions,
  autoFocus,
  keepAfterIssue = {},
  onResult,
  onIssued,
}: {
  title: string;
  action?: ReactNode;
  intro: ReactNode;
  initial: ProvisionValues;
  endpoint: string;
  submitLabel: string;
  /** Подпись кнопки после первой выдачи. */
  submitAgainLabel?: string;
  balanceLabel?: string;
  extraRam?: number;
  factions?: string[];
  autoFocus?: boolean;
  /** Что подставить в форму после выдачи (например, очистить позывной для следующего игрока). */
  keepAfterIssue?: Partial<ProvisionValues>;
  onResult: (result: ProvisionQr) => void;
  onIssued?: (values: ProvisionValues) => void;
}) {
  const [values, setValues] = useState<ProvisionValues>(initial);
  const [issued, setIssued] = useState(false);
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось выдать" });
  const { data } = useApiData<ProvisionsResponse>("/api/provisions", { pollMs: false });

  async function submit() {
    const res = await run(() =>
      api.post<ProvisionQr>(endpoint, { callsign: values.callsign, faction: values.faction, balance: Number(values.balance) || 0, ram: Number(values.ram) }),
    );
    if (!res.ok) return;
    onResult(res.value);
    onIssued?.(values);
    setIssued(true);
    setValues((v) => ({ ...v, ...keepAfterIssue }));
  }

  return (
    <Panel title={title} action={action}>
      <div className="master-form">
        <p className="hint-text">{intro}</p>
        {data && <ProvisionConfigNote config={data.config} />}
        <ProvisionFields values={values} onChange={setValues} factions={factions} extraRam={extraRam} balanceLabel={balanceLabel} autoFocus={autoFocus} />
        {error && <div className="login-error">{error}</div>}
        <AppButton variant="primary" onClick={submit} disabled={busy || !values.callsign.trim()}>
          {busy ? "Выдаю…" : issued ? submitAgainLabel : submitLabel}
        </AppButton>
      </div>
    </Panel>
  );
}
