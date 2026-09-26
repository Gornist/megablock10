import { useState } from "react";
import type { ChangeRow } from "../api/types";
import { reasonLabel, useMeta } from "../api/useMeta";
import { formatDateTime, formatTime, shortKey } from "../format";

/**
 * Одна запись изменения для ленты и истории: слева цветной маркер типа события, дальше фраза («перевод 100 €$ → Bob»),
 * а сырые поля (field, old → new, код причины, source_ref, ключи) спрятаны под «детали» — нужны для отладки, не для чтения.
 * showSubject — в общей ленте перед фразой стоит позывной игрока; в истории конкретного игрока он лишний.
 */
export function ChangeLine({ row, showSubject, time = "received", withDate = false }: { row: ChangeRow; showSubject: boolean; time?: "received" | "happened"; withDate?: boolean }) {
  const [open, setOpen] = useState(false);
  const meta = useMeta();
  const human = row.human;
  const kind = human?.kind ?? "system";
  return (
    <div className={`change-line kind-${kind}`}>
      <div className="change-line-main">
        <span className="change-marker" />
        {kind === "master" && <span className="change-kind-tag mono status-caps">мастер</span>}
        <span className="change-time mono">{(withDate ? formatDateTime : formatTime)(time === "received" ? row.received_at : row.happened_at)}</span>
        <span className="change-text">
          {showSubject && human && <strong className="change-subject">{human.subject}: </strong>}
          {human ? human.body : `${row.field}: ${row.old_value ?? "∅"} → ${row.new_value ?? "∅"}`}
        </span>
        <button type="button" className="change-toggle" onClick={() => setOpen((v) => !v)} aria-expanded={open}>
          {open ? "скрыть" : "детали"}
        </button>
      </div>
      {open && (
        <dl className="change-details mono">
          <dt>Событие</dt>
          <dd>{reasonLabel(meta, row.reason)} <span className="hint-text">({row.reason})</span></dd>
          <dt>Поле</dt>
          <dd>{row.field}</dd>
          <dt>Было → стало</dt>
          <dd className="change-raw">{row.old_value ?? "∅"} → {row.new_value ?? "∅"}</dd>
          {row.source_ref && (<><dt>Источник</dt><dd>{row.source_ref}</dd></>)}
          <dt>Игрок</dt>
          <dd>{shortKey(row.subject_key, 14)}</dd>
          {row.actor !== row.subject_key && (<><dt>Инициатор</dt><dd>{shortKey(row.actor, 14)}</dd></>)}
          <dt>Запись</dt>
          <dd>{row.id} · seq {row.seq}</dd>
        </dl>
      )}
    </div>
  );
}
