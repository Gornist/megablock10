import { AppInput, AppSelect, Field } from "../../design/components";
import { RAM_OPTIONS, ramLabel } from "./provisionUtil";

export interface ProvisionValues {
  callsign: string;
  faction: string;
  balance: string;
  ram: string;
}

/** Общие поля выдачи персонажа: форма «Персонаж» в Мастерской и «Выдать заново» на карточке игрока показывают один и тот же набор. */
export function ProvisionFields({
  values,
  onChange,
  factions = [],
  extraRam,
  balanceLabel = "Стартовый баланс, эдди",
  autoFocus,
}: {
  values: ProvisionValues;
  onChange: (next: ProvisionValues) => void;
  /** Подсказки для поля фракции. */
  factions?: string[];
  /** Текущий RAM игрока, если его нет среди стандартных вариантов. */
  extraRam?: number;
  balanceLabel?: string;
  autoFocus?: boolean;
}) {
  const set = (patch: Partial<ProvisionValues>) => onChange({ ...values, ...patch });
  const rams = [...new Set(extraRam === undefined ? RAM_OPTIONS : [...RAM_OPTIONS, extraRam])].sort((a, b) => a - b);
  return (
    <>
      <Field label="Позывной">
        <AppInput value={values.callsign} maxLength={40} onChange={(e) => set({ callsign: e.target.value })} placeholder="Alice" autoFocus={autoFocus} />
      </Field>
      <Field label="Фракция">
        <AppInput value={values.faction} maxLength={40} list="provision-factions" onChange={(e) => set({ faction: e.target.value })} placeholder="Neon" />
        <datalist id="provision-factions">
          {factions.map((f) => (
            <option key={f} value={f} />
          ))}
        </datalist>
      </Field>
      <Field label={balanceLabel}>
        <AppInput value={values.balance} onChange={(e) => set({ balance: e.target.value.replace(/\D/g, "") })} placeholder="0" />
      </Field>
      <Field label="Ёмкость буфера RAM">
        <AppSelect value={values.ram} onChange={(e) => set({ ram: e.target.value })}>
          {rams.map((r) => (
            <option key={r} value={r}>
              {ramLabel(r)}
            </option>
          ))}
        </AppSelect>
      </Field>
    </>
  );
}
