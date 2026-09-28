import { useState } from "react";
import { api } from "../../api/client";
import type { DisplayGroup, DisplayItem, DisplaySecretResponse } from "../../api/types";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppInput, AppSelect, Field, Panel } from "../../design/components";
import { ToggleField } from "../master/common";

interface Draft {
  id: string;
  name: string;
  ip: string;
  port: string;
  width: string;
  height: string;
  enabled: boolean;
  /** "" — без группы. */
  groupId: string;
  /** "" — без узла. */
  nodeId: string;
}

const NEW_DRAFT: Draft = { id: "", name: "", ip: "", port: "47200", width: "792", height: "272", enabled: true, groupId: "", nodeId: "" };

function toDraft(d: DisplayItem): Draft {
  return {
    id: d.id,
    name: d.name,
    ip: d.ip,
    port: String(d.port),
    width: String(d.width),
    height: String(d.height),
    enabled: d.enabled,
    groupId: d.groupId ?? "",
    nodeId: d.nodeId ?? "",
  };
}

const digits = (v: string) => v.replace(/\D/g, "");

/**
 * Новая точка (id задаётся один раз — он прошит в плату) или правка существующей: имя, локация, узел, постоянный IP, порт,
 * размер панели. Узел — контейнер, которым точка стоит в мире; одна точка на узел, занятые узлы в списке недоступны.
 */
export function DisplayForm({
  editing,
  groups,
  nodes = [],
  takenNodes = new Map(),
  defaultGroupId,
  onCreated,
  onSaved,
  onCancel,
}: {
  editing?: DisplayItem;
  groups: DisplayGroup[];
  /** Узлы (контейнеры) для выбора. */
  nodes?: { id: string; name: string }[];
  /** Узел → id точки, которая на нём стоит. */
  takenNodes?: Map<string, string>;
  /** Новый дисплей из группы («+ дисплей» в её заголовке) — сразу в неё. */
  defaultGroupId?: string;
  onCreated: (r: DisplaySecretResponse) => void;
  onSaved: () => void;
  onCancel: () => void;
}) {
  const [draft, setDraft] = useState<Draft>(editing ? toDraft(editing) : { ...NEW_DRAFT, groupId: defaultGroupId ?? "" });
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось сохранить" });
  const set = (patch: Partial<Draft>) => setDraft((d) => ({ ...d, ...patch }));

  async function submit() {
    const body = {
      name: draft.name,
      ip: draft.ip.trim(),
      port: Number(draft.port),
      width: Number(draft.width),
      height: Number(draft.height),
      enabled: draft.enabled,
      groupId: draft.groupId || null,
      nodeId: draft.nodeId || null,
    };
    if (editing) {
      const res = await run(() => api.put<DisplayItem>(`/api/displays/${encodeURIComponent(editing.id)}`, body));
      if (res.ok) onSaved();
    } else {
      const res = await run(() => api.post<DisplaySecretResponse>("/api/displays", { id: draft.id.trim(), ...body }));
      if (res.ok) onCreated(res.value);
    }
  }

  return (
    <Panel title={editing ? `Точка ${editing.id}` : "Новая точка"}>
      <div className="master-form">
        {!editing && (
          <Field label="id (прошивается в плату, потом не меняется)">
            <AppInput value={draft.id} onChange={(e) => set({ id: e.target.value })} placeholder="display-017" />
          </Field>
        )}
        <Field label="Название точки">
          <AppInput value={draft.name} onChange={(e) => set({ name: e.target.value })} placeholder="Точка 17, техэтаж" />
        </Field>
        <Field label="Локация">
          <AppSelect value={draft.groupId} onChange={(e) => set({ groupId: e.target.value })} aria-label="группа">
            <option value="">без локации</option>
            {groups.map((g) => (
              <option key={g.id} value={g.id}>
                {g.name}
              </option>
            ))}
          </AppSelect>
        </Field>
        <Field label="Узел (контейнер, которым точка стоит в мире)">
          <AppSelect value={draft.nodeId} onChange={(e) => set({ nodeId: e.target.value })} aria-label="узел">
            <option value="">без узла — просто динамик в локации</option>
            {nodes.map((n) => {
              const other = takenNodes.get(n.id);
              const busy = other !== undefined && other !== editing?.id;
              return (
                <option key={n.id} value={n.id} disabled={busy}>
                  {n.name}
                  {busy ? ` — занят (${other})` : ""}
                </option>
              );
            })}
          </AppSelect>
        </Field>
        <Field label="IP-адрес (постоянный, выдан роутером)">
          <AppInput value={draft.ip} onChange={(e) => set({ ip: e.target.value })} placeholder="10.10.0.217" />
        </Field>
        <Field label="TCP-порт">
          <AppInput value={draft.port} onChange={(e) => set({ port: digits(e.target.value) })} placeholder="47200" />
        </Field>
        <Field label="Панель, px: ширина × высота (CrowPanel 5.79 горизонтально — 792 × 272)">
          <div className="filter-row">
            <AppInput value={draft.width} onChange={(e) => set({ width: digits(e.target.value) })} placeholder="792" />
            <AppInput value={draft.height} onChange={(e) => set({ height: digits(e.target.value) })} placeholder="272" />
          </div>
        </Field>
        <ToggleField label="Включён" value={draft.enabled} onToggle={() => set({ enabled: !draft.enabled })} />
        {error && <div className="login-error">{error}</div>}
        <div className="filter-row">
          <AppButton variant="primary" onClick={submit} disabled={busy || !draft.name.trim() || !draft.ip.trim() || (!editing && !draft.id.trim())}>
            {busy ? "Сохраняю…" : editing ? "Сохранить" : "Добавить"}
          </AppButton>
          <AppButton onClick={onCancel}>отмена</AppButton>
        </div>
      </div>
    </Panel>
  );
}

/**
 * Секрет и что прошить в плату — показывается один раз, сервер его больше не отдаст. «Со звуком» — точка со звуковой платой
 * (microSD + MAX98357A, docs/sound-nodes.md): в строку настройки добавляется роль audio.
 */
export function SecretPanel({ result, onClose }: { result: DisplaySecretResponse; onClose: () => void }) {
  const [audio, setAudio] = useState(false);
  const config = JSON.stringify(
    { ...result.provisioning, wifiSsid: "<SSID>", wifiPassword: "<пароль>", ...(audio ? { roles: ["display", "audio"] } : {}) },
    null,
    2,
  );
  return (
    <Panel title={`Секрет дисплея ${result.display.id}`} action={<AppButton onClick={onClose}>скрыть</AppButton>}>
      <p className="hint-text">
        Показывается один раз — запишите в плату сейчас (docs/displays.md, «Первичная настройка»). Потеряли — «Новый секрет» и прошить заново.
      </p>
      <code className="secret-box mono">{result.secret}</code>
      <label className="sound-check">
        <input type="checkbox" checked={audio} onChange={(e) => setAudio(e.target.checked)} /> со звуком (карта и усилитель) — точка появится в «Громкой связи»
      </label>
      <pre className="qr-raw mono">{config}</pre>
    </Panel>
  );
}
