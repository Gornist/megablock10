import { useState } from "react";
import { api } from "../../api/client";
import type { AudioClip, NetPointLinkItem, NetState, WorldEventActionItem, WorldEventKindInfo, WorldEventsConfig, WorldEventsTestResult } from "../../api/types";
import { POLL_RELAXED_MS } from "../../api/pollIntervals";
import { useApiData } from "../../api/useApiData";
import { AsyncPanel } from "../../design/AsyncPanel";
import { AppButton, AppInput, AppSelect, Badge, ErrorNote, Panel } from "../../design/components";
import { docsOf, useNetCall } from "./netUtil";

function ActionRow({ kind, action, clips, testing, onSaved, onTest }: { kind: WorldEventKindInfo; action: WorldEventActionItem | undefined; clips: AudioClip[]; testing: boolean; onSaved: () => void; onTest: () => void }) {
  const { busy, error, call } = useNetCall(onSaved);
  const saved = { clipId: action?.clipId ?? "", volume: action?.volume === null || action?.volume === undefined ? "" : String(action.volume), chime: action?.chime ?? true, enabled: action?.enabled ?? false };
  const [draft, setDraft] = useState(saved);
  const dirty = JSON.stringify(draft) !== JSON.stringify(saved);
  const volume = draft.volume.trim() === "" ? null : Number(draft.volume);
  const volumeOk = volume === null || (Number.isInteger(volume) && volume >= 0 && volume <= 100);

  return (
    <tr>
      <td>
        {kind.label}
        <div className="hint-text">{kind.when}</div>
      </td>
      <td>
        <AppSelect value={draft.clipId} onChange={(e) => setDraft({ ...draft, clipId: e.target.value, enabled: e.target.value !== "" ? true : false })} aria-label={`клип: ${kind.label}`}>
          <option value="">— ничего —</option>
          {clips.map((c) => (
            <option key={c.id} value={c.id}>{c.name}</option>
          ))}
        </AppSelect>
      </td>
      <td>
        <AppInput inputMode="numeric" value={draft.volume} placeholder="80" onChange={(e) => setDraft({ ...draft, volume: e.target.value })} aria-label={`громкость: ${kind.label}`} style={{ width: 64 }} />
      </td>
      <td>
        <label className="sound-check"><input type="checkbox" checked={draft.chime} onChange={(e) => setDraft({ ...draft, chime: e.target.checked })} /> гонг</label>
      </td>
      <td>
        <label className="sound-check"><input type="checkbox" checked={draft.enabled} onChange={(e) => setDraft({ ...draft, enabled: e.target.checked })} /> вкл</label>
      </td>
      <td>
        <span className="filter-row filter-wrap">
          <AppButton variant="primary" disabled={!dirty || !volumeOk || busy} onClick={() => void call(() => api.put(`/api/net/world-events/actions/${encodeURIComponent(kind.kind)}`, { clipId: draft.clipId || null, volume, chime: draft.chime, enabled: draft.enabled }))}>
            сохранить
          </AppButton>
          <AppButton disabled={testing || dirty} onClick={onTest}>проверить</AppButton>
        </span>
        {error && <ErrorNote>{error}</ErrorNote>}
      </td>
    </tr>
  );
}

function LinkRow({ link, onSaved }: { link: NetPointLinkItem; onSaved: () => void }) {
  const { busy, error, call } = useNetCall(onSaved);
  const [node, setNode] = useState(link.netNode ?? "");
  const [terminal, setTerminal] = useState(link.terminal ?? "");
  const dirty = node !== (link.netNode ?? "") || terminal !== (link.terminal ?? "");
  return (
    <tr>
      <td>{link.displayName} <span className="mono hint-text">{link.displayId}</span></td>
      <td><AppInput list="net-node-ids" value={node} onChange={(e) => setNode(e.target.value.trim())} placeholder="узел Сети" aria-label={`узел Сети: ${link.displayName}`} /></td>
      <td><AppInput list="net-terminal-ids" value={terminal} onChange={(e) => setTerminal(e.target.value.trim())} placeholder="терминал" aria-label={`терминал: ${link.displayName}`} /></td>
      <td>
        <AppButton variant="primary" disabled={!dirty || busy} onClick={() => void call(() => api.put(`/api/net/point-links/${encodeURIComponent(link.displayId)}`, { netNode: node || null, terminal: terminal || null }))}>
          сохранить
        </AppButton>
        {error && <ErrorNote>{error}</ErrorNote>}
      </td>
    </tr>
  );
}

/**
 * Площадка: что звучит на точках, когда в Сети что-то происходит (быстрые события Моста), и какие точки к какому узлу/терминалу
 * привязаны. Работает и без Моста — это настройки коллектора. По умолчанию события ничего не играют.
 */
export function VenuePanel({ state }: { state: NetState | null }) {
  const { data: config, error, reload } = useApiData<WorldEventsConfig>("/api/net/world-events/config", { pollMs: false });
  const { data: clips } = useApiData<AudioClip[]>("/api/audio/clips", { pollMs: POLL_RELAXED_MS });
  const [testNode, setTestNode] = useState("");
  const [testTerminal, setTestTerminal] = useState("");
  const [result, setResult] = useState<{ kind: string; r: WorldEventsTestResult } | null>(null);
  const test = useNetCall(() => undefined);

  const nodeIds = docsOf(state, "node").map((d) => d.id);
  const terminalIds = docsOf(state, "terminal").map((d) => d.id);

  return (
    <Panel title="Площадка: звуки событий Сети">
      <datalist id="net-node-ids">{[...new Set([...nodeIds, ...(config?.links.map((l) => l.netNode).filter(Boolean) as string[] ?? [])])].map((id) => <option key={id} value={id} />)}</datalist>
      <datalist id="net-terminal-ids">{[...new Set([...terminalIds, ...(config?.links.map((l) => l.terminal).filter(Boolean) as string[] ?? [])])].map((id) => <option key={id} value={id} />)}</datalist>
      <AsyncPanel data={config} error={error}>
        {(c) => (
          <>
            <p className="hint-text">
              Событие идёт на точки, привязанные к его терминалу или узлу, и играет выбранный клип на звуковых точках. «Проверить» шлёт то же событие, что пришло бы от Моста, — на указанный узел и терминал.
            </p>
            <div className="filter-row filter-wrap">
              <AppInput list="net-node-ids" value={testNode} onChange={(e) => setTestNode(e.target.value.trim())} placeholder="проверка: узел" aria-label="узел для проверки" />
              <AppInput list="net-terminal-ids" value={testTerminal} onChange={(e) => setTestTerminal(e.target.value.trim())} placeholder="проверка: терминал" aria-label="терминал для проверки" />
              {result && (
                <Badge tone={result.r.playedOn.length > 0 ? "ok" : "warn"}>
                  {result.r.playedOn.length > 0 ? `${result.kind}: сыграло на ${result.r.playedOn.join(", ")}` : `${result.kind}: ничего не сыграло — нет клипа или звуковой точки`}
                </Badge>
              )}
            </div>
            {test.error && <ErrorNote>{test.error}</ErrorNote>}
            <table className="data-table">
              <thead>
                <tr><th>Событие</th><th>Клип</th><th>Громкость</th><th /><th /><th /></tr>
              </thead>
              <tbody>
                {c.kinds
                  .filter((k) => k.byTerminal || k.byNode)
                  .map((k) => (
                    <ActionRow
                      key={`${k.kind}:${JSON.stringify(c.actions.find((a) => a.kind === k.kind))}`}
                      kind={k}
                      action={c.actions.find((a) => a.kind === k.kind)}
                      clips={clips ?? []}
                      testing={test.busy}
                      onSaved={reload}
                      onTest={() =>
                        void test.call(async () => {
                          const r = await api.post<WorldEventsTestResult>("/api/net/world-events/test", { kind: k.kind, node: testNode || undefined, terminal: testTerminal || undefined });
                          setResult({ kind: k.label, r });
                        })
                      }
                    />
                  ))}
              </tbody>
            </table>
            <p className="hint-text">«{c.kinds.find((k) => !k.byTerminal && !k.byNode)?.label ?? "Зов мастера"}» на площадку не идёт — только звонок в панели мастера («Требует внимания» в Обзоре).</p>
            <h4 className="status-caps">Точки ↔ узлы и терминалы Сети</h4>
            {c.links.length === 0 ? (
              <p className="hint-text">точек пока нет — добавьте устройства на экране «Устройства»</p>
            ) : (
              <table className="data-table">
                <thead>
                  <tr><th>Точка</th><th>Узел Сети</th><th>Терминал</th><th /></tr>
                </thead>
                <tbody>
                  {c.links.map((l) => (
                    <LinkRow key={`${l.displayId}:${l.netNode}:${l.terminal}`} link={l} onSaved={reload} />
                  ))}
                </tbody>
              </table>
            )}
          </>
        )}
      </AsyncPanel>
    </Panel>
  );
}
