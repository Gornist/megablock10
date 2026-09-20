import type { Attention } from "../../api/types";
import { useApiData } from "../../api/useApiData";
import { AsyncPanel } from "../../design/AsyncPanel";
import { Badge, Panel } from "../../design/components";
import { formatAgo } from "../../format";
import { navigate } from "../../router";

/**
 * «Требует внимания» — автоподсказки сервера (lib/attention.ts): отрицательный
 * баланс, крупные поступления, пропавшие игроки, недоставленные правки и т.п.
 * Клик по строке ведёт к игроку/узлу, о котором речь.
 */
export function AttentionPanel() {
  const { data, error } = useApiData<Attention>("/api/attention", { pollMs: 10000 });
  const counts = data?.counts;

  return (
    <Panel
      title="Требует внимания"
      action={
        counts && (
          <span className="filter-row">
            {counts.crit > 0 && <Badge tone="danger">срочно {counts.crit}</Badge>}
            {counts.warn > 0 && <Badge tone="accent">важно {counts.warn}</Badge>}
            {counts.info > 0 && <Badge>к сведению {counts.info}</Badge>}
          </span>
        )
      }
    >
      <AsyncPanel data={data} error={error} isEmpty={(d) => d.items.length === 0} emptyLabel="всё спокойно">
        {(d) =>
          d.items.map((i) => {
            const go = i.subjectKey ? () => navigate("players", i.subjectKey!) : i.nodeId ? () => navigate("nodes", i.nodeId!) : undefined;
            return (
              <div key={i.id} className={`attn-item sev-${i.severity} ${go ? "clickable" : ""}`} onClick={go}>
                <span className="attn-title">{i.title}</span>
                <span className="attn-detail">{i.detail}</span>
                <span className="attn-time mono">{formatAgo(i.at)}</span>
              </div>
            );
          })
        }
      </AsyncPanel>
    </Panel>
  );
}
