import type { BulkPreview, PlayerListItem } from "../../api/types";
import { formatNumber } from "../../format";

/** Предпросмотр массовой правки: «кому что изменится» (было → станет). */
export function BulkPreviewList({ preview, field, players }: { preview: BulkPreview; field: string; players: PlayerListItem[] }) {
  const nameOf = (key: string) => players.find((p) => p.publicKeyB64 === key)?.callsign || key.slice(0, 8);
  const show = (v: string | null) => (field === "balance" && v !== null ? formatNumber(Number(v)) : (v ?? "∅"));
  return (
    <>
      <p className="hint-text">
        {preview.target}: изменится у {preview.count}, без изменений — {preview.unchanged}.
      </p>
      <div className="feed-list">
        {(preview.changes ?? []).map((c) => (
          <div key={c.publicKeyB64} className="slot-row">
            <span>{c.callsign || nameOf(c.publicKeyB64)}</span>
            <span className="mono">
              {show(c.oldValue)} → {show(c.newValue)}
            </span>
          </div>
        ))}
      </div>
    </>
  );
}
