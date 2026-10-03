import { useRef, useState } from "react";
import { api } from "../../api/client";
import type { NetState, NetStockResult, NodeStockView } from "../../api/types";
import { POLL_LIVE_MS } from "../../api/pollIntervals";
import { useApiData, usePolledData } from "../../api/useApiData";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppInput, AppSelect, Badge, ErrorNote, Field, Panel } from "../../design/components";
import { newRef } from "../net/netUtil";
import { TierPicker, type TierName } from "./common";
import { EMPTY_SHARD_DRAFT, ShardFields, shardDraftToPayload, type ShardDraft } from "./ShardFields";

const EFFECTS: { value: string; label: string }[] = [
  { value: "EXTRACT_SHARD", label: "извлечь шард" },
  { value: "EXTRACT_DAEMON", label: "извлечь демона" },
  { value: "GHOST", label: "призрак — убирает ID из сигнала СБ" },
  { value: "TIMESKEW", label: "отсрочка сигнала СБ на 10 минут" },
  { value: "BLACKOUT", label: "блэкаут — сигнал СБ не уходит" },
  { value: "JITTER", label: "+15 секунд к попытке" },
  { value: "DECRYPT", label: "дешифратор" },
  { value: "MINER", label: "майнер — добавочные эдди" },
];

/** Предмет в «корзине» закладки: шард или демон в человеческом виде; payload для Моста собирает коллектор. */
type Draft = ({ type: "SHARD"; tier: TierName } & ReturnType<typeof shardDraftToPayload>) | { type: "DAEMON"; tier: TierName; name: string; sequence: string[]; effect: string };

const label = (d: Draft) => (d.type === "SHARD" ? `шард «${d.title}»` : `демон «${d.name}» (${d.sequence.join(" ")})`);

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

  const [cart, setCart] = useState<Draft[]>([]);
  const [addEddies, setAddEddies] = useState("0");
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [takeEddies, setTakeEddies] = useState("0");
  const [kind, setKind] = useState<"SHARD" | "DAEMON">("SHARD");
  const [tier, setTier] = useState<TierName>("BASE");
  const [shard, setShard] = useState<ShardDraft>(EMPTY_SHARD_DRAFT);
  const [daemon, setDaemon] = useState({ name: "", codes: "", effect: "EXTRACT_SHARD" });
  const [done, setDone] = useState<string | null>(null);
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось связаться с сервером" });
  const rids = useRef(new Map<string, string>());

  /** Один и тот же набор параметров — один и тот же rid; другой набор — новый. */
  const ridFor = (key: string) => {
    if (!rids.current.has(key)) rids.current.set(key, newRef("stock"));
    return rids.current.get(key)!;
  };

  const codes = daemon.codes.split(/[\s,]+/).filter(Boolean);
  const canAddShard = shard.title.trim() !== "" && shard.body.trim() !== "";
  const canAddDaemon = daemon.name.trim() !== "" && codes.length > 0;
  const eddiesIn = Math.max(0, Math.floor(Number(addEddies) || 0));
  const eddiesOut = Math.max(0, Math.floor(Number(takeEddies) || 0));

  function addToCart() {
    setCart((c) => [...c, kind === "SHARD" ? { type: "SHARD", tier, ...shardDraftToPayload(shard) } : { type: "DAEMON", tier, name: daemon.name.trim(), sequence: codes, effect: daemon.effect }]);
    if (kind === "SHARD") setShard(EMPTY_SHARD_DRAFT);
    else setDaemon({ ...daemon, name: "", codes: "" });
  }

  async function stockNode() {
    const body = { items: cart, eddies: eddiesIn };
    const res = await run(() => api.post<NetStockResult>(`/api/net/nodes/${encodeURIComponent(node)}/stock`, { rid: ridFor(`stock:${node}:${JSON.stringify(body)}`), ...body }));
    if (res.ok) {
      setDone(`В узел ${node} положено: предметов ${res.value.items.length}${eddiesIn ? `, эдди +${eddiesIn}` : ""}${res.value.replayed ? " (повтор — уже было выполнено)" : ""}. Запас эдди: ${res.value.eddies}.`);
      setCart([]);
      setAddEddies("0");
      reload();
    }
  }

  async function unstockNode() {
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
        {stock && (
          <>
            <p>
              <span className="status-caps">запас эдди:</span> <span className="mono">{stock.eddies ?? "—"}</span>
            </p>
            {stock.items.length === 0 ? (
              <p className="hint-text">Предметов в узле нет.</p>
            ) : (
              stock.items.map((i) => (
                <label key={i.id} className="sound-check" style={{ display: "block" }}>
                  <input type="checkbox" checked={picked.has(i.id)} onChange={(e) => setPicked((p) => { const n = new Set(p); if (e.target.checked) n.add(i.id); else n.delete(i.id); return n; })} />{" "}
                  <Badge tone={i.kind === "SHARD" ? "info" : "accent"}>{i.kind === "SHARD" ? "шард" : "демон"}</Badge> {i.title || i.id}
                  {i.tier ? <span className="hint-text"> · тир {i.tier}</span> : null}
                  {i.effect ? <span className="hint-text"> · {i.effect}</span> : null}
                  <span className="hint-text mono"> · {i.id}</span>
                </label>
              ))
            )}
            <div className="filter-row filter-wrap">
              <AppInput inputMode="numeric" value={takeEddies} onChange={(e) => setTakeEddies(e.target.value.replace(/\D/g, ""))} aria-label="сколько эдди убрать" style={{ width: 96 }} />
              <span className="hint-text">эдди убрать</span>
              <AppButton variant="danger" disabled={busy || (picked.size === 0 && eddiesOut === 0)} onClick={() => void unstockNode()}>
                убрать выбранное
              </AppButton>
            </div>
          </>
        )}
      </Panel>

      <Panel title="Добавить в узел">
        <div className="master-form">
          <div className="filter-row">
            <AppButton variant={kind === "SHARD" ? "primary" : "default"} onClick={() => setKind("SHARD")}>шард</AppButton>
            <AppButton variant={kind === "DAEMON" ? "primary" : "default"} onClick={() => setKind("DAEMON")}>демон</AppButton>
          </div>
          <Field label="Тир">
            <TierPicker value={tier} onChange={setTier} />
          </Field>
          {kind === "SHARD" ? (
            <ShardFields value={shard} onChange={(patch) => setShard((d) => ({ ...d, ...patch }))} />
          ) : (
            <>
              <Field label="Имя демона">
                <AppInput value={daemon.name} onChange={(e) => setDaemon({ ...daemon, name: e.target.value })} placeholder="Призрак" />
              </Field>
              <Field label="Цепочка кодов (через пробел или запятую)">
                <AppInput value={daemon.codes} onChange={(e) => setDaemon({ ...daemon, codes: e.target.value })} placeholder="1C BD 55" />
              </Field>
              <Field label="Эффект">
                <AppSelect value={daemon.effect} onChange={(e) => setDaemon({ ...daemon, effect: e.target.value })} aria-label="эффект демона">
                  {EFFECTS.map((f) => (
                    <option key={f.value} value={f.value}>{f.label}</option>
                  ))}
                </AppSelect>
              </Field>
            </>
          )}
          <AppButton disabled={kind === "SHARD" ? !canAddShard : !canAddDaemon} onClick={addToCart}>
            в корзину
          </AppButton>
        </div>
        {cart.length > 0 && (
          <div>
            <h4 className="status-caps">К закладке ({cart.length})</h4>
            {cart.map((d, i) => (
              <div key={i} className="filter-row">
                <span>{label(d)} · {d.tier}</span>
                <button type="button" className="change-toggle" onClick={() => setCart((c) => c.filter((_, j) => j !== i))}>убрать</button>
              </div>
            ))}
          </div>
        )}
        <div className="filter-row filter-wrap">
          <AppInput inputMode="numeric" value={addEddies} onChange={(e) => setAddEddies(e.target.value.replace(/\D/g, ""))} aria-label="сколько эдди добавить" style={{ width: 96 }} />
          <span className="hint-text">эдди добавить</span>
          <AppButton variant="primary" disabled={busy || !node || (cart.length === 0 && eddiesIn === 0)} onClick={() => void stockNode()}>
            положить в узел
          </AppButton>
        </div>
      </Panel>
    </>
  );
}
