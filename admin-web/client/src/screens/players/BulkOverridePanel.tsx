import { useState } from "react";
import { api } from "../../api/client";
import type { BulkPreview, PlayerListItem, TargetSelector } from "../../api/types";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppInput, AppSelect, Field, Panel } from "../../design/components";
import { formatNumber } from "../../format";

const FIELD_LABEL: Record<string, string> = { balance: "Эдди", ramCapacity: "Буфер RAM (6–13)", faction: "Фракция" };

interface Props {
  players: PlayerListItem[];
  selectedKeys: string[];
  /** Фракция, выбранная фильтром списка — «всем этой фракции» без ручного отмечания. */
  factionFilter: string;
  onDone: () => void;
  onClose: () => void;
}

/**
 * Массовая правка: одно значение и одно основание — сразу выбранным игрокам,
 * фракции целиком или всем. Всегда сначала предпросмотр («кому что
 * изменится»), и «Применить» доступно только для того предпросмотра, что
 * соответствует текущей форме — ошибка на сотню игроков дороже одиночной.
 */
export function BulkOverridePanel({ players, selectedKeys, factionFilter, onDone, onClose }: Props) {
  const [target, setTarget] = useState<"selected" | "faction" | "all">(selectedKeys.length > 0 ? "selected" : factionFilter ? "faction" : "all");
  const [field, setField] = useState("balance");
  const [mode, setMode] = useState<"add" | "set">("add");
  const [value, setValue] = useState("");
  const [reason, setReason] = useState("");
  const [preview, setPreview] = useState<{ form: string; data: BulkPreview } | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось выполнить" });

  const effectiveMode = field === "faction" ? "set" : mode;
  const selector: TargetSelector =
    target === "selected" ? { keys: selectedKeys } : target === "faction" ? { faction: factionFilter } : { all: true };
  const request = { ...selector, field, newValue: value, mode: effectiveMode, reason };
  const formKey = JSON.stringify(request);
  const ready = value.trim() !== "" && reason.trim() !== "" && !(target === "selected" && selectedKeys.length === 0) && !(target === "faction" && !factionFilter);
  const previewFresh = preview?.form === formKey ? preview.data : null;
  const nameOf = (key: string) => players.find((p) => p.publicKeyB64 === key)?.callsign || key.slice(0, 8);

  async function doPreview() {
    setDone(null);
    const res = await run(() => api.post<BulkPreview>("/api/players/bulk-override", { ...request, dryRun: true }));
    if (res.ok) setPreview({ form: formKey, data: res.value });
  }

  async function apply() {
    const res = await run(() => api.post<BulkPreview>("/api/players/bulk-override", request));
    if (res.ok) {
      setDone(`Готово: ${res.value.target}, изменено ${res.value.count} чел.`);
      setPreview(null);
      setValue("");
      setReason("");
      onDone();
    }
  }

  return (
    <Panel title="Массовая правка" action={<AppButton onClick={onClose}>закрыть</AppButton>}>
      <div className="bulk-form">
        <div className="bulk-grid">
          <Field label="Кому">
            <AppSelect value={target} onChange={(e) => setTarget(e.target.value as typeof target)}>
              <option value="selected" disabled={selectedKeys.length === 0}>
                выбранным ({selectedKeys.length})
              </option>
              <option value="faction" disabled={!factionFilter}>
                {factionFilter ? `фракции «${factionFilter}»` : "фракции (выберите в фильтре)"}
              </option>
              <option value="all">всем ({players.length})</option>
            </AppSelect>
          </Field>
          <Field label="Что">
            <AppSelect value={field} onChange={(e) => setField(e.target.value)}>
              {Object.entries(FIELD_LABEL).map(([k, l]) => (
                <option key={k} value={k}>
                  {l}
                </option>
              ))}
            </AppSelect>
          </Field>
          {field !== "faction" && (
            <Field label="Как">
              <AppSelect value={mode} onChange={(e) => setMode(e.target.value as "add" | "set")}>
                <option value="add">прибавить (можно с минусом)</option>
                <option value="set">установить</option>
              </AppSelect>
            </Field>
          )}
        </div>
        <Field label={field === "faction" ? "Новая фракция" : effectiveMode === "add" ? "Сколько прибавить" : "Новое значение"}>
          <AppInput value={value} onChange={(e) => setValue(e.target.value)} placeholder={field === "faction" ? "NEON_DRAGONS" : "+200"} />
        </Field>
        <Field label="Основание (обязательно, попадёт в журнал)">
          <AppInput value={reason} onChange={(e) => setReason(e.target.value)} placeholder="премия за акт 2" />
        </Field>
        {error && <div className="login-error">{error}</div>}
        {done && <div className="hint-text">{done}</div>}
        <div className="bulk-grid">
          <AppButton onClick={doPreview} disabled={busy || !ready}>
            Предпросмотр
          </AppButton>
          <AppButton variant="primary" onClick={apply} disabled={busy || !previewFresh || previewFresh.count === 0}>
            {busy ? "…" : `Применить${previewFresh ? ` (${previewFresh.count})` : ""}`}
          </AppButton>
        </div>
        {previewFresh && (
          <>
            <p className="hint-text">
              {previewFresh.target}: изменится у {previewFresh.count}, без изменений — {previewFresh.unchanged}.
            </p>
            <div className="feed-list">
              {(previewFresh.changes ?? []).map((c) => (
                <div key={c.publicKeyB64} className="slot-row">
                  <span>{c.callsign || nameOf(c.publicKeyB64)}</span>
                  <span className="mono">
                    {field === "balance" && c.oldValue !== null ? formatNumber(Number(c.oldValue)) : (c.oldValue ?? "∅")} →{" "}
                    {field === "balance" ? formatNumber(Number(c.newValue)) : c.newValue}
                  </span>
                </div>
              ))}
            </div>
          </>
        )}
      </div>
    </Panel>
  );
}
