import { AppButton, AppInput, AppSelect, Field, Panel } from "../../design/components";
import { TierPicker } from "./common";
import { ShardFields } from "./ShardFields";
import { type Draft, type StockDraft } from "./useStockDraft";

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

const label = (d: Draft) => (d.type === "SHARD" ? `шард «${d.title}»` : `демон «${d.name}» (${d.sequence.join(" ")})`);

/** Форма «Добавить в узел»: выбор шарда/демона, корзина и эдди; саму закладку (rid, запрос) выполняет StockForm через onStock. */
export function StockAddForm({ draft, busy, node, onStock }: { draft: StockDraft; busy: boolean; node: string; onStock: () => void }) {
  const { cart, eddiesIn, addEddies, kind, tier, shard, daemon } = draft;
  return (
    <Panel title="Добавить в узел">
      <div className="master-form">
        <div className="filter-row">
          <AppButton variant={kind === "SHARD" ? "primary" : "default"} onClick={() => draft.setKind("SHARD")}>шард</AppButton>
          <AppButton variant={kind === "DAEMON" ? "primary" : "default"} onClick={() => draft.setKind("DAEMON")}>демон</AppButton>
        </div>
        <Field label="Тир">
          <TierPicker value={tier} onChange={draft.setTier} />
        </Field>
        {kind === "SHARD" ? (
          <ShardFields value={shard} onChange={(patch) => draft.setShard((d) => ({ ...d, ...patch }))} />
        ) : (
          <>
            <Field label="Имя демона">
              <AppInput value={daemon.name} onChange={(e) => draft.setDaemon({ ...daemon, name: e.target.value })} placeholder="Призрак" />
            </Field>
            <Field label="Цепочка кодов (через пробел или запятую)">
              <AppInput value={daemon.codes} onChange={(e) => draft.setDaemon({ ...daemon, codes: e.target.value })} placeholder="1C BD 55" />
            </Field>
            <Field label="Эффект">
              <AppSelect value={daemon.effect} onChange={(e) => draft.setDaemon({ ...daemon, effect: e.target.value })} aria-label="эффект демона">
                {EFFECTS.map((f) => (
                  <option key={f.value} value={f.value}>{f.label}</option>
                ))}
              </AppSelect>
            </Field>
          </>
        )}
        <AppButton disabled={!draft.canAdd} onClick={draft.addToCart}>
          в корзину
        </AppButton>
      </div>
      {cart.length > 0 && (
        <div>
          <h4 className="status-caps">К закладке ({cart.length})</h4>
          {cart.map((d, i) => (
            <div key={i} className="filter-row">
              <span>{label(d)} · {d.tier}</span>
              <button type="button" className="change-toggle" onClick={() => draft.removeFromCart(i)}>убрать</button>
            </div>
          ))}
        </div>
      )}
      <div className="filter-row filter-wrap">
        <AppInput inputMode="numeric" value={addEddies} onChange={(e) => draft.setAddEddies(e.target.value.replace(/\D/g, ""))} aria-label="сколько эдди добавить" style={{ width: 96 }} />
        <span className="hint-text">эдди добавить</span>
        <AppButton variant="primary" disabled={busy || !node || (cart.length === 0 && eddiesIn === 0)} onClick={onStock}>
          положить в узел
        </AppButton>
      </div>
    </Panel>
  );
}
