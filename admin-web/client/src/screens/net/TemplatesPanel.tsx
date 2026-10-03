import { useState } from "react";
import { api } from "../../api/client";
import type { NetDoc, NetState } from "../../api/types";
import { AppButton, AppDialog, ErrorNote, Panel } from "../../design/components";
import { docsOf, obj, text, useNetCall } from "./netUtil";

/** Заготовки Сети: набор настроек и параметров узлов, применяется к выбранным узлам одной командой (одна транзакция в Мосте). */
export function TemplatesPanel({ state, reload }: { state: NetState; reload: () => void }) {
  const { busy, error, call } = useNetCall(reload);
  const [target, setTarget] = useState<NetDoc | null>(null);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const templates = docsOf(state, "template");
  const nodes = docsOf(state, "node");
  if (templates.length === 0 && !error) return null;

  const needsNodes = target !== null && Object.keys(obj(target.data.node_cfg)).length > 0;

  return (
    <Panel title={`Заготовки (${templates.length})`}>
      {error && <ErrorNote>{error}</ErrorNote>}
      {templates.map((t) => (
        <div key={t.id} className="attn-item sev-info">
          <span className="attn-title">{text(t.data.title) || t.id}</span>
          <span className="attn-detail hint-text">
            {t.id}
            {Object.keys(obj(t.data.settings)).length > 0 ? ` · настройки: ${Object.keys(obj(t.data.settings)).join(", ")}` : ""}
            {Object.keys(obj(t.data.node_cfg)).length > 0 ? ` · на узлы: ${Object.keys(obj(t.data.node_cfg)).join(", ")}` : ""}
          </span>
          <AppButton
            disabled={busy}
            onClick={() => {
              setPicked(new Set());
              setTarget(t);
            }}
          >
            применить…
          </AppButton>
        </div>
      ))}
      {target && (
        <AppDialog
          title={`Применить «${text(target.data.title) || target.id}»`}
          body={needsNodes ? "Выберите узлы, на которые лягут параметры заготовки. Общие настройки применятся ко всей Сети." : "Заготовка меняет только общие настройки Сети."}
          confirmText="Применить"
          confirmDisabled={needsNodes && picked.size === 0}
          onCancel={() => setTarget(null)}
          onConfirm={() => {
            const id = target.id;
            const list = [...picked];
            setTarget(null);
            void call(() => api.post("/api/net/template/apply", { template: id, ...(list.length > 0 ? { nodes: list } : {}) }));
          }}
        >
          {needsNodes &&
            nodes.map((n) => (
              <label key={n.id} className="sound-check">
                <input
                  type="checkbox"
                  checked={picked.has(n.id)}
                  onChange={(e) =>
                    setPicked((p) => {
                      const next = new Set(p);
                      if (e.target.checked) next.add(n.id);
                      else next.delete(n.id);
                      return next;
                    })
                  }
                />{" "}
                <span className="mono">{n.id}</span> {text(n.data.title)}
              </label>
            ))}
        </AppDialog>
      )}
    </Panel>
  );
}
