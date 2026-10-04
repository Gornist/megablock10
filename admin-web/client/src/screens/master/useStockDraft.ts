import { useState } from "react";
import type { TierName } from "./common";
import { EMPTY_SHARD_DRAFT, shardDraftToPayload, type ShardDraft } from "./ShardFields";

/** Предмет в «корзине» закладки: шард или демон в человеческом виде; payload для Моста собирает коллектор. */
export type Draft = ({ type: "SHARD"; tier: TierName } & ReturnType<typeof shardDraftToPayload>) | { type: "DAEMON"; tier: TierName; name: string; sequence: string[]; effect: string };

/**
 * Черновик закладки: корзина, эдди и поля формы. Состояние живёт в StockForm (а не в StockAddForm), чтобы корзина не терялась,
 * пока форма скрыта из-за обрыва Моста.
 */
export function useStockDraft() {
  const [cart, setCart] = useState<Draft[]>([]);
  const [addEddies, setAddEddies] = useState("0");
  const [kind, setKind] = useState<"SHARD" | "DAEMON">("SHARD");
  const [tier, setTier] = useState<TierName>("BASE");
  const [shard, setShard] = useState<ShardDraft>(EMPTY_SHARD_DRAFT);
  const [daemon, setDaemon] = useState({ name: "", codes: "", effect: "EXTRACT_SHARD" });

  const codes = daemon.codes.split(/[\s,]+/).filter(Boolean);

  function addToCart() {
    setCart((c) => [...c, kind === "SHARD" ? { type: "SHARD", tier, ...shardDraftToPayload(shard) } : { type: "DAEMON", tier, name: daemon.name.trim(), sequence: codes, effect: daemon.effect }]);
    if (kind === "SHARD") setShard(EMPTY_SHARD_DRAFT);
    else setDaemon({ ...daemon, name: "", codes: "" });
  }

  return {
    cart,
    eddiesIn: Math.max(0, Math.floor(Number(addEddies) || 0)),
    addEddies,
    setAddEddies,
    kind,
    setKind,
    tier,
    setTier,
    shard,
    setShard,
    daemon,
    setDaemon,
    canAdd: kind === "SHARD" ? shard.title.trim() !== "" && shard.body.trim() !== "" : daemon.name.trim() !== "" && codes.length > 0,
    addToCart,
    removeFromCart: (index: number) => setCart((c) => c.filter((_, j) => j !== index)),
    /** После успешной закладки: корзина и эдди обнуляются, поля формы остаются. */
    clearStocked: () => {
      setCart([]);
      setAddEddies("0");
    },
  };
}

export type StockDraft = ReturnType<typeof useStockDraft>;
