import { useState } from "react";
import { AppButton, Badge, Panel } from "../../design/components";
import { DisplayPushDialog } from "../displays/DisplayPushDialog";
import type { DisplaySource } from "../displays/displayUtil";

const TIERS = ["BASE", "HARD", "NIGHTMARE"] as const;
export type TierName = (typeof TIERS)[number];
export const TIER_LABEL: Record<TierName, string> = { BASE: "База", HARD: "Сложно", NIGHTMARE: "Кошмар" };

export interface QrResult {
  qr: string;
  qrImage: string;
}

export function TierPicker({ value, onChange }: { value: TierName; onChange: (t: TierName) => void }) {
  return (
    <div className="filter-row">
      {TIERS.map((t) => (
        <Badge key={t} tone={t === value ? "accent" : "neutral"}>
          <span className="tier-pick" onClick={() => onChange(t)}>
            {TIER_LABEL[t]}
          </span>
        </Badge>
      ))}
    </div>
  );
}

export function ToggleField({ label, value, onToggle }: { label: string; value: boolean; onToggle: () => void }) {
  return (
    <label className="status-caps status-toggle" onClick={onToggle}>
      <Badge tone={value ? "accent" : "neutral"}>
        {label}: {value ? "да" : "нет"}
      </Badge>
    </label>
  );
}

/**
 * Готовый QR: печать (картинка) и, если задан displaySource, «На дисплей» — тот же QR на электронную точку (сервер рисует кадр из той
 * же строки, см. docs/displays.md).
 */
export function QrPanel({ result, caption, displaySource }: { result: QrResult; caption: string; displaySource?: DisplaySource }) {
  const [pushing, setPushing] = useState(false);
  return (
    <Panel title="Готово" action={displaySource && <AppButton onClick={() => setPushing(true)}>На дисплей</AppButton>}>
      <div className="qr-panel">
        <img src={result.qrImage} alt="QR" width={260} height={260} />
        <p className="mono qr-caption">{caption}</p>
        <p className="hint-text">Сфотографируйте или напечатайте до игры — появится у игрока сразу после скана.</p>
        <details>
          <summary className="hint-text">сырая строка QR</summary>
          <code className="qr-raw mono">{result.qr}</code>
        </details>
      </div>
      {pushing && displaySource && <DisplayPushDialog source={displaySource} title={caption} onClose={() => setPushing(false)} />}
    </Panel>
  );
}
