import { Badge, Panel } from "../../design/components";

export const TIERS = ["BASE", "HARD", "NIGHTMARE"] as const;
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

export function QrPanel({ result, caption }: { result: QrResult; caption: string }) {
  return (
    <Panel title="Готово">
      <div className="qr-panel">
        <img src={result.qrImage} alt="QR" width={260} height={260} />
        <p className="mono qr-caption">{caption}</p>
        <p className="hint-text">Сфотографируйте или напечатайте до игры — появится у игрока сразу после скана.</p>
        <details>
          <summary className="hint-text">сырая строка QR</summary>
          <code className="qr-raw mono">{result.qr}</code>
        </details>
      </div>
    </Panel>
  );
}
