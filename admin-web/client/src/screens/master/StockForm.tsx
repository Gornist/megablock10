import { useRef, useState } from "react";
import { api } from "../../api/client";
import type { NetState, NetStockResult, NodeStockView } from "../../api/types";
import { POLL_LIVE_MS } from "../../api/pollIntervals";
import { useApiData, usePolledData } from "../../api/useApiData";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppSelect, ErrorNote, Panel } from "../../design/components";
import { newRef } from "../net/netUtil";
import { StockAddForm } from "./StockAddForm";
import { StockList } from "./StockList";
import { useStockDraft } from "./useStockDraft";

/**
 * Наполнение узла Сети: что лежит в узле сейчас, добавить шарды/демонов/эдди и убрать лишнее. Это операции с ценностями: rid создаётся
 * один раз на нажатие и не меняется при повторе (ошибка сети, двойной клик) — Мост выполнит операцию один раз. Изменили корзину после
 * неудачи — rid новый, иначе Мост отверг бы «те же» параметры с другим содержимым.
 */
export function StockForm() {
  const { data: state } = useApiData<NetState>("/api/net/state", { pollMs: POLL_LIVE_MS });
  const nodes = state?.bridge === "connected" ? (state.docs.node ?? []) : [];
  const [nodeId, setNodeId] = useState("");
  const node = nodeId || nodes[0]?.id || "";
  const { data: loaded, reload } = usePolledData<NodeStockView | null>(() => (node ? api.get<NodeStockView>(`/api/net/nodes/${encodeURIComponent(node)}/items`) : Promise.resolve(null)), { pollMs: POLL_LIVE_MS, key: node });
  // После смены узла в данных ещё прежний узел до следующего ответа — его предметы с галочками не показываем.
  const stock = loaded && loaded.node === node ? loaded : null;

  const draft = useStockDraft();
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [takeEddies, setTakeEddies] = useState("0");
  const [done, setDone] = useState<string | null>(null);
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось связаться с сервером" });
  const rids = useRef(new Map<string, string>());

  /** Один и тот же набор параметров — один и тот же rid; другой набор — новый. */
  const ridFor = (key: string) => {
    if (!rids.current.has(key)) rids.current.set(key, newRef("stock"));
    return rids.current.get(key)!;
  };

  async function stockNode() {
    const { cart, eddiesIn } = draft;
    const body = { items: cart, eddies: eddiesIn };
    const res = await run(() => api.post<NetStockResult>(`/api/net/nodes/${encodeURIComponent(node)}/stock`, { rid: ridFor(`stock:${node}:${JSON.stringify(body)}`), ...body }));
    if (res.ok) {
      setDone(`В узел ${node} положено: предметов ${res.value.items.length}${eddiesIn ? `, эдди +${eddiesIn}` : ""}${res.value.replayed ? " (повтор — уже было выполнено)" : ""}. Запас эдди: ${res.value.eddies}.`);
      draft.clearStocked();
      reload();
    }
  }

  async function unstockNode(eddiesOut: number) {
    const body = { items: [...picked].sort(), eddies: eddiesOut };
    const res = await run(() => api.post<NetStockResult>(`/api/net/nodes/${encodeURIComponent(node)}/unstock`, { rid: ridFor(`unstock:${node}:${JSON.stringify(body)}`), ...body }));
    if (res.ok) {
      setDone(`Из узла ${node} убрано: предметов ${res.value.items.length}${eddiesOut ? `, эдди −${eddiesOut}` : ""}. Остаток эдди: ${res.value.eddies}.`);
      setPicked(new Set());
      setTakeEddies("0");
      reload();
    }
  }

  if (state && state.bridge !== "connected") {
    return (
      <Panel title="Наполнение узла Сети">
        <p className="hint-text">{state.bridge === "disabled" ? "Мост не настроен — наполнять узлы нечем." : "Мост недоступен — наполнение узлов станет доступно, когда он вернётся."}</p>
      </Panel>
    );
  }

  return (
    <>
      <Panel
        title="Наполнение узла Сети"
        action={
          <AppSelect value={node} onChange={(e) => { setNodeId(e.target.value); setPicked(new Set()); setDone(null); }} aria-label="узел Сети">
            {nodes.map((n) => (
              <option key={n.id} value={n.id}>{n.id} · {String(n.data.title ?? "")}</option>
            ))}
          </AppSelect>
        }
      >
        <p className="hint-text">Шарды, демоны и эдди кладутся в узел: нетраннер найдёт их в забеге. Убранное уходит в журнал Моста (burned:master), эдди вычитаются из запаса.</p>
        {error && <ErrorNote>{error}</ErrorNote>}
        {done && <div className="asof-banner">{done}</div>}
        {nodes.length === 0 && state && <p className="hint-text">В Мосте нет узлов.</p>}
        {stock && <StockList stock={stock} picked={picked} onPickedChange={setPicked} takeEddies={takeEddies} onTakeEddiesChange={setTakeEddies} busy={busy} onUnstock={(eddiesOut) => void unstockNode(eddiesOut)} />}
      </Panel>

      <StockAddForm draft={draft} busy={busy} node={node} onStock={() => void stockNode()} />
    </>
  );
}
