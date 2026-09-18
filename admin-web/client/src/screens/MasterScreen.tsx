import { useState } from "react";
import { api, ApiError } from "../api/client";
import { useApiData } from "../api/useApiData";
import { AppButton, AppInput, AppSelect, Badge, EmptyState, ErrorNote, Field, Panel } from "../design/components";
import { formatTime } from "../format";

const TIERS = ["BASE", "HARD", "NIGHTMARE"] as const;
type TierName = (typeof TIERS)[number];
const TIER_LABEL: Record<TierName, string> = { BASE: "База", HARD: "Сложно", NIGHTMARE: "Кошмар" };

const DAEMON_CODES = ["1C", "55", "BD", "E9", "7A", "FF"];
const DAEMON_EFFECTS = [
  { value: "EXTRACT_SHARD", label: "извлекает шард из контейнера" },
  { value: "EXTRACT_DAEMON", label: "извлекает демона из контейнера" },
  { value: "GHOST", label: "убирает ID из сигнала СБ" },
  { value: "TIMESKEW", label: "+10 мин к задержке сигнала СБ" },
  { value: "BLACKOUT", label: "сигнал СБ не отправляется" },
  { value: "JITTER", label: "+15 сек к таймеру попытки" },
];

const SUB_TABS = ["Контейнер", "Шард", "RAM", "Мастера"] as const;

export function MasterScreen() {
  const [tab, setTab] = useState<(typeof SUB_TABS)[number]>("Контейнер");
  return (
    <div className="screen-grid">
      <p className="hint-text master-intro">
        Генерирует QR для контейнеров, шардов и RAM-апгрейдов — печатайте или показывайте с экрана заранее, до игры. То же шифрование и тот же формат,
        что раньше был только в Мастерской на телефоне — игрок сканирует как обычно, разницы не видно.
      </p>
      <div className="filter-row">
        {SUB_TABS.map((t) => (
          <AppButton key={t} variant={t === tab ? "primary" : "default"} onClick={() => setTab(t)}>
            {t}
          </AppButton>
        ))}
      </div>
      {tab === "Контейнер" && <ContainerForm />}
      {tab === "Шард" && <ShardForm />}
      {tab === "RAM" && <RamForm />}
      {tab === "Мастера" && <MastersTab />}
    </div>
  );
}

function TierPicker({ value, onChange }: { value: TierName; onChange: (t: TierName) => void }) {
  return (
    <div className="filter-row">
      {TIERS.map((t) => (
        <Badge key={t} tone={t === value ? "accent" : "neutral"}>
          <span className="tier-pick" onClick={() => onChange(t)}>
            {TIER_LABEL[t]}
          </span>
        </Badge>
      ))}
    </div>
  );
}

function ToggleField({ label, value, onToggle }: { label: string; value: boolean; onToggle: () => void }) {
  return (
    <label className="status-caps status-toggle" onClick={onToggle}>
      <Badge tone={value ? "accent" : "neutral"}>
        {label}: {value ? "да" : "нет"}
      </Badge>
    </label>
  );
}

interface SlotDraft {
  type: "SHARD" | "DAEMON";
  tier: TierName;
  copies: number;
  title: string;
  shard?: { title: string; meta: string; body: string; valueHint: string; decryptAction: boolean; moneyAmount: number };
  daemon?: { name: string; sequence: string[]; effect: string };
}

interface QrResult {
  qr: string;
  qrImage: string;
}

function QrPanel({ result, caption }: { result: QrResult; caption: string }) {
  return (
    <Panel title="Готово">
      <div className="qr-panel">
        <img src={result.qrImage} alt="QR" width={260} height={260} />
        <p className="mono qr-caption">{caption}</p>
        <p className="hint-text">Сфотографируйте или напечатайте до игры — появится у игрока сразу после скана.</p>
        <details>
          <summary className="hint-text">сырая строка QR</summary>
          <code className="qr-raw mono">{result.qr}</code>
        </details>
      </div>
    </Panel>
  );
}

function ContainerForm() {
  const [id, setId] = useState("");
  const [name, setName] = useState("");
  const [tier, setTier] = useState<TierName>("BASE");
  const [ownerFaction, setOwnerFaction] = useState("");
  const [slots, setSlots] = useState<SlotDraft[]>([]);
  const [result, setResult] = useState<QrResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      const res = await api.post<{ containerId: string; qr: string; qrImage: string }>("/api/master/containers", {
        id: id || undefined,
        name,
        tier,
        ownerFaction,
        slots: slots.map((s) => ({ type: s.type, tier: s.tier, copies: s.copies, shard: s.shard, daemon: s.daemon })),
      });
      setResult(res);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "не удалось сгенерировать");
    } finally {
      setBusy(false);
    }
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

  const [shardTitle, setShardTitle] = useState("");
  const [shardMeta, setShardMeta] = useState("");
  const [shardBody, setShardBody] = useState("");
  const [shardValueHint, setShardValueHint] = useState("");
  const [shardDecryptAction, setShardDecryptAction] = useState(false);
  const [shardMoney, setShardMoney] = useState("0");

  const [daemonName, setDaemonName] = useState("");
  const [daemonSequence, setDaemonSequence] = useState<string[]>([]);
  const [daemonEffect, setDaemonEffect] = useState("EXTRACT_SHARD");

  const canAdd = type === "SHARD" ? shardTitle.trim() && shardBody.trim() : daemonName.trim() && daemonSequence.length > 0;

  function add() {
    const base = { type, tier, copies: Number(copies) || 0 };
    if (type === "SHARD") {
      onAdd({
        ...base,
        title: shardTitle,
        shard: { title: shardTitle, meta: shardMeta, body: shardBody, valueHint: shardValueHint, decryptAction: shardDecryptAction, moneyAmount: Number(shardMoney) || 0 },
      });
      setShardTitle("");
      setShardMeta("");
      setShardBody("");
      setShardValueHint("");
      setShardDecryptAction(false);
      setShardMoney("0");
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
          <>
            <Field label="Заголовок шарда">
              <AppInput value={shardTitle} onChange={(e) => setShardTitle(e.target.value)} placeholder="Служебный лог клиники" />
            </Field>
            <Field label="Мета-строка">
              <AppInput value={shardMeta} onChange={(e) => setShardMeta(e.target.value)} placeholder="получен 21:02 · клиника" />
            </Field>
            <Field label="Текст шарда">
              <textarea className="app-input master-textarea" value={shardBody} onChange={(e) => setShardBody(e.target.value)} placeholder="Полный текст, который увидит игрок" />
            </Field>
            <Field label="Подсказка ценности">
              <AppInput value={shardValueHint} onChange={(e) => setShardValueHint(e.target.value)} placeholder="ценный технический документ" />
            </Field>
            <ToggleField label="требует взлома" value={shardDecryptAction} onToggle={() => setShardDecryptAction(!shardDecryptAction)} />
            <Field label="Деньги в шарде, €$">
              <AppInput value={shardMoney} onChange={(e) => setShardMoney(e.target.value.replace(/\D/g, ""))} placeholder="0" />
            </Field>
          </>
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

function ShardForm() {
  const [id, setId] = useState("");
  const [decryptAction, setDecryptAction] = useState(false);
  const [tier, setTier] = useState<TierName>("BASE");
  const [valueHint, setValueHint] = useState("");
  const [title, setTitle] = useState("");
  const [meta, setMeta] = useState("");
  const [body, setBody] = useState("");
  const [money, setMoney] = useState("0");
  const [result, setResult] = useState<QrResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      const res = await api.post<{ shardId: string; qr: string; qrImage: string }>("/api/master/shards", {
        id: id || undefined,
        decryptAction,
        tier,
        valueHint,
        title,
        meta,
        body,
        moneyAmount: Number(money) || 0,
      });
      setResult(res);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "не удалось сгенерировать");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Panel title="Шард">
        <div className="master-form">
          <Field label="id (можно не менять)">
            <AppInput value={id} onChange={(e) => setId(e.target.value)} placeholder="shard-xxxxxxxx" />
          </Field>
          <Field label="Тир (длина цели расшифровки)">
            <TierPicker value={tier} onChange={setTier} />
          </Field>
          <ToggleField label="требует взлома" value={decryptAction} onToggle={() => setDecryptAction(!decryptAction)} />
          <Field label="Заголовок">
            <AppInput value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Служебный лог клиники" />
          </Field>
          <Field label="Мета-строка">
            <AppInput value={meta} onChange={(e) => setMeta(e.target.value)} placeholder="получен 21:02 · клиника, уровень доступа 2" />
          </Field>
          <Field label="Текст шарда">
            <textarea className="app-input master-textarea" value={body} onChange={(e) => setBody(e.target.value)} placeholder="Полный текст, который увидит игрок" />
          </Field>
          <Field label="Подсказка ценности">
            <AppInput value={valueHint} onChange={(e) => setValueHint(e.target.value)} placeholder="ценный технический документ" />
          </Field>
          <Field label="Деньги в шарде, €$">
            <AppInput value={money} onChange={(e) => setMoney(e.target.value.replace(/\D/g, ""))} placeholder="0" />
          </Field>
          {error && <div className="login-error">{error}</div>}
          <AppButton variant="primary" onClick={submit} disabled={busy || !title || !body}>
            {busy ? "Генерирую…" : "Показать QR"}
          </AppButton>
        </div>
      </Panel>
      {result && <QrPanel result={result} caption={title} />}
    </>
  );
}

function RamForm() {
  const [delta, setDelta] = useState("1");
  const [result, setResult] = useState<QrResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      const res = await api.post<{ token: string; qr: string; qrImage: string }>("/api/master/ram", { delta: Number(delta) || 1 });
      setResult(res);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "не удалось сгенерировать");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Panel title="RAM-апгрейд">
        <div className="master-form">
          <p className="hint-text">Каждый QR одноразовый на устройство игрока — генерируйте новый для каждой выдачи.</p>
          <Field label="Прибавка к RAM, ячеек">
            <AppInput value={delta} onChange={(e) => setDelta(e.target.value.replace(/\D/g, ""))} placeholder="1" />
          </Field>
          {error && <div className="login-error">{error}</div>}
          <AppButton variant="primary" onClick={submit} disabled={busy || !(Number(delta) > 0)}>
            {busy ? "Генерирую…" : "Показать QR"}
          </AppButton>
        </div>
      </Panel>
      {result && <QrPanel result={result} caption={`+${delta} RAM`} />}
    </>
  );
}

interface MasterAccount {
  id: string;
  name: string;
  createdAt: number;
}

function MastersTab() {
  const { data: masters, error, reload } = useApiData<MasterAccount[]>("/api/masters");
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);
  const [created, setCreated] = useState<{ name: string; token: string } | null>(null);

  async function create() {
    setBusy(true);
    setCreateError(null);
    try {
      const res = await api.post<{ name: string; token: string }>("/api/masters", { name });
      setCreated(res);
      setName("");
      reload();
    } catch (err) {
      setCreateError(err instanceof ApiError ? err.message : "не удалось создать");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Panel title="Новый мастер">
        <div className="master-form">
          <Field label="Имя">
            <AppInput value={name} onChange={(e) => setName(e.target.value)} placeholder="Мастер Два" />
          </Field>
          {createError && <div className="login-error">{createError}</div>}
          <AppButton variant="primary" onClick={create} disabled={busy || !name.trim()}>
            {busy ? "Создаю…" : "Создать"}
          </AppButton>
        </div>
      </Panel>
      {created && (
        <Panel title="Готово">
          <p>
            Мастер «{created.name}» создан. Токен для входа — <strong className="mono">{created.token}</strong>
          </p>
          <p className="hint-text">Больше нигде не показывается — на сервере хранится только хэш. Передайте его новому мастеру сейчас, здесь и сейчас.</p>
        </Panel>
      )}
      <Panel title="Все мастера">
        {error && <ErrorNote>{error}</ErrorNote>}
        {masters === null ? (
          <EmptyState>загрузка…</EmptyState>
        ) : (
          masters.map((m) => (
            <div key={m.id} className="slot-row">
              <span>{m.name}</span>
              <span className="hint-text">с {formatTime(m.createdAt)}</span>
            </div>
          ))
        )}
      </Panel>
    </>
  );
}
