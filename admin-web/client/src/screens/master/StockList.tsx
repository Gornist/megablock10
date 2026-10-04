import type { NodeStockView } from "../../api/types";
import { AppButton, AppInput, Badge } from "../../design/components";

interface StockListProps {
  stock: NodeStockView;
  /** id предметов с галочкой; состояние держит StockForm — оно переживает смену узла и обрыв Моста. */
  picked: Set<string>;
  onPickedChange: (next: Set<string>) => void;
  takeEddies: string;
  onTakeEddiesChange: (v: string) => void;
  busy: boolean;
  /** Убрать выбранное и столько эдди (уже целое, ≥ 0). */
  onUnstock: (eddiesOut: number) => void;
}

/** Запас узла: эдди, предметы с галочками и «убрать выбранное». Сами операции (rid, запрос) — в StockForm. */
export function StockList({ stock, picked, onPickedChange, takeEddies, onTakeEddiesChange, busy, onUnstock }: StockListProps) {
  const eddiesOut = Math.max(0, Math.floor(Number(takeEddies) || 0));
  return (
    <>
      <p>
        <span className="status-caps">запас эдди:</span> <span className="mono">{stock.eddies ?? "—"}</span>
      </p>
      {stock.items.length === 0 ? (
        <p className="hint-text">Предметов в узле нет.</p>
      ) : (
        stock.items.map((i) => (
          <label key={i.id} className="sound-check" style={{ display: "block" }}>
            <input
              type="checkbox"
              checked={picked.has(i.id)}
              onChange={(e) => {
                const next = new Set(picked);
                if (e.target.checked) next.add(i.id);
                else next.delete(i.id);
                onPickedChange(next);
              }}
            />{" "}
            <Badge tone={i.kind === "SHARD" ? "info" : "accent"}>{i.kind === "SHARD" ? "шард" : "демон"}</Badge> {i.title || i.id}
            {i.tier ? <span className="hint-text"> · тир {i.tier}</span> : null}
            {i.effect ? <span className="hint-text"> · {i.effect}</span> : null}
            <span className="hint-text mono"> · {i.id}</span>
          </label>
        ))
      )}
      <div className="filter-row filter-wrap">
        <AppInput inputMode="numeric" value={takeEddies} onChange={(e) => onTakeEddiesChange(e.target.value.replace(/\D/g, ""))} aria-label="сколько эдди убрать" style={{ width: 96 }} />
        <span className="hint-text">эдди убрать</span>
        <AppButton variant="danger" disabled={busy || (picked.size === 0 && eddiesOut === 0)} onClick={() => onUnstock(eddiesOut)}>
          убрать выбранное
        </AppButton>
      </div>
    </>
  );
}
