import { useState } from "react";
import { api } from "../../api/client";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppInput, AppSelect, EmptyState, Field, Panel } from "../../design/components";
import { QrPanel, type QrResult, TIER_LABEL, type TierName, TierPicker } from "./common";
import { EMPTY_SHARD_DRAFT, ShardFields, shardDraftToPayload, type ShardDraft } from "./ShardFields";

const DAEMON_CODES = ["1C", "55", "BD", "E9", "7A", "FF"];
const DAEMON_EFFECTS = [
  { value: "EXTRACT_SHARD", label: "извлекает шард из контейнера" },
  { value: "EXTRACT_DAEMON", label: "извлекает демона из контейнера" },
  { value: "GHOST", label: "убирает ID из сигнала СБ" },
  { value: "TIMESKEW", label: "+10 мин к задержке сигнала СБ" },
  { value: "BLACKOUT", label: "сигнал СБ не отправляется" },
  { value: "JITTER", label: "+15 сек к таймеру попытки" },
  { value: "DECRYPT", label: "расшифровывает зашифрованные шарды" },
  { value: "MINER", label: "добывает эдди из взломанного узла" },
];

interface SlotDraft {
  type: "SHARD" | "DAEMON";
  tier: TierName;
  copies: number;
  title: string;
  shard?: ReturnType<typeof shardDraftToPayload>;
  daemon?: { name: string; sequence: string[]; effect: string };
}

export function ContainerForm() {
  const [id, setId] = useState("");
  const [name, setName] = useState("");
  const [tier, setTier] = useState<TierName>("BASE");
  const [ownerFaction, setOwnerFaction] = useState("");
  const [slots, setSlots] = useState<SlotDraft[]>([]);
  const [result, setResult] = useState<QrResult | null>(null);
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось сгенерировать" });

  async function submit() {
    const res = await run(() =>
      api.post<{ containerId: string; qr: string; qrImage: string }>("/api/master/containers", {
        id: id || undefined,
        name,
        tier,
        ownerFaction,
        slots: slots.map((s) => ({ type: s.type, tier: s.tier, copies: s.copies, shard: s.shard, daemon: s.daemon })),
      }),
    );
    if (res.ok) setResult(res.value);
  }

  return (
    <>
      <Panel title="Контейнер">
        <div className="master-form">
          <Field label="id (можно не менять)">
            <AppInput value={id} onChange={(e) => setId(e.target.value)} placeholder="container-xxxxxxxx" />
          </Field>
          <Field label="Название">
            <AppInput value={name} onChange={(e) => setName(e.target.value)} placeholder="Панель вентиляции, техэтаж" />
          </Field>
          <Field label="Тир (сложность взлома)">
            <TierPicker value={tier} onChange={setTier} />
          </Field>
          <Field label="Фракция-владелец (получает сигнал СБ)">
            <AppInput value={ownerFaction} onChange={(e) => setOwnerFaction(e.target.value)} placeholder="Otryad_SB" />
          </Field>

          <Field label={`Лут — ${slots.length} слот(ов)`}>
            {slots.length === 0 ? (
              <EmptyState>пока пусто</EmptyState>
            ) : (
              slots.map((s, i) => (
                <div key={i} className="slot-row">
                  <span>
                    {s.type === "SHARD" ? `Шард: ${s.shard?.title}` : `Демон: ${s.daemon?.name}`} · {TIER_LABEL[s.tier]} · {s.copies === 0 ? "∞" : s.copies}
                  </span>
                  <AppButton variant="danger" onClick={() => setSlots(slots.filter((_, j) => j !== i))}>
                    убрать
                  </AppButton>
                </div>
              ))
            )}
          </Field>
          <SlotBuilder onAdd={(slot) => setSlots([...slots, slot])} />

          {error && <div className="login-error">{error}</div>}
          <AppButton variant="primary" onClick={submit} disabled={busy || !name || !ownerFaction}>
            {busy ? "Генерирую…" : "Показать QR"}
          </AppButton>
        </div>
      </Panel>
      {result && <QrPanel result={result} caption={name} />}
    </>
  );
}

function SlotBuilder({ onAdd }: { onAdd: (slot: SlotDraft) => void }) {
  const [type, setType] = useState<"SHARD" | "DAEMON">("SHARD");
  const [tier, setTier] = useState<TierName>("BASE");
  const [copies, setCopies] = useState("0");

  const [shardDraft, setShardDraft] = useState<ShardDraft>(EMPTY_SHARD_DRAFT);

  const [daemonName, setDaemonName] = useState("");
  const [daemonSequence, setDaemonSequence] = useState<string[]>([]);
  const [daemonEffect, setDaemonEffect] = useState("EXTRACT_SHARD");

  const canAdd = type === "SHARD" ? shardDraft.title.trim() && shardDraft.body.trim() : daemonName.trim() && daemonSequence.length > 0;

  function add() {
    const base = { type, tier, copies: Number(copies) || 0 };
    if (type === "SHARD") {
      onAdd({ ...base, title: shardDraft.title, shard: shardDraftToPayload(shardDraft) });
      setShardDraft(EMPTY_SHARD_DRAFT);
    } else {
      onAdd({ ...base, title: daemonName, daemon: { name: daemonName, sequence: daemonSequence, effect: daemonEffect } });
      setDaemonName("");
      setDaemonSequence([]);
    }
    setCopies("0");
  }

  return (
    <Panel title="Новый слот" className="slot-builder">
      <div className="master-form">
        <div className="filter-row">
          <AppButton variant={type === "SHARD" ? "primary" : "default"} onClick={() => setType("SHARD")}>
            Шард
          </AppButton>
          <AppButton variant={type === "DAEMON" ? "primary" : "default"} onClick={() => setType("DAEMON")}>
            Демон
          </AppButton>
        </div>
        <TierPicker value={tier} onChange={setTier} />
        <Field label="Тираж (0 — без ограничения)">
          <AppInput value={copies} onChange={(e) => setCopies(e.target.value.replace(/\D/g, ""))} placeholder="0" />
        </Field>

        {type === "SHARD" ? (
          <ShardFields value={shardDraft} onChange={(patch) => setShardDraft((d) => ({ ...d, ...patch }))} />
        ) : (
          <>
            <Field label="Название демона">
              <AppInput value={daemonName} onChange={(e) => setDaemonName(e.target.value)} placeholder="Backdoor.exe" />
            </Field>
            <Field label="Код-последовательность (кликайте по порядку)">
              <div className="filter-row">
                {DAEMON_CODES.map((code) => (
                  <AppButton key={code} onClick={() => setDaemonSequence([...daemonSequence, code])}>
                    {code}
                  </AppButton>
                ))}
              </div>
            </Field>
            <div className="sequence-row">
              {daemonSequence.length === 0 ? <span className="hint-text">пока пусто</span> : <span className="mono">{daemonSequence.join(" ")}</span>}
              {daemonSequence.length > 0 && (
                <AppButton variant="danger" onClick={() => setDaemonSequence([])}>
                  очистить
                </AppButton>
              )}
            </div>
            <Field label="Эффект при совпадении">
              <AppSelect value={daemonEffect} onChange={(e) => setDaemonEffect(e.target.value)}>
                {DAEMON_EFFECTS.map((eff) => (
                  <option key={eff.value} value={eff.value}>
                    {eff.label}
                  </option>
                ))}
              </AppSelect>
            </Field>
          </>
        )}

        <AppButton onClick={add} disabled={!canAdd}>
          Добавить слот в контейнер
        </AppButton>
      </div>
    </Panel>
  );
}
