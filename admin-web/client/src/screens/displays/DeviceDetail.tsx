import { useState } from "react";
import { api } from "../../api/client";
import type { AudioChannel, DisplayGroup, DisplayItem, DisplayPreview, DisplaySecretResponse } from "../../api/types";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppDialog, AppSelect, Panel } from "../../design/components";
import { navigate } from "../../router";
import { PointAudioBlock } from "../audio/PointAudio";
import { DeviceFacts } from "./DeviceFacts";
import { PushSteps } from "./DisplayMock";
import { DisplayPushDialog } from "./DisplayPushDialog";
import { isLagging } from "./useDisplayFrame";
import { StatusAndBattery } from "./DeviceStatus";
import { phaseText, type DisplaySource } from "./displayUtil";

const BACKLIGHT = [
  { value: "OFF", label: "выкл" },
  { value: "LOW", label: "слабо" },
  { value: "MEDIUM", label: "средне" },
  { value: "HIGH", label: "ярко" },
];
/** Подсветка из дашборда — для проверки на месте; гаснет сама, чтобы не посадить батарею забытой командой. */
const BACKLIGHT_SECONDS = 20;

type Confirm = "reboot" | "secret" | "delete";

/** Опасные команды карточки — спрашиваем подтверждение. */
const CONFIRM: Record<Confirm, { title: string; body: (id: string) => string; confirmText: string }> = {
  reboot: { title: "Перезагрузить дисплей?", body: (id) => `${id} перезагрузится и восстановит последний кадр.`, confirmText: "Перезагрузить" },
  secret: {
    title: "Сменить секрет?",
    body: (id) => `Старый секрет перестанет работать: ${id} придётся прошить новым, до этого он не примет ни одной картинки.`,
    confirmText: "Сменить",
  },
  delete: { title: "Удалить дисплей?", body: (id) => `${id} пропадёт из списка; на панели останется последний кадр.`, confirmText: "Удалить" },
};

/**
 * Канонiчная карточка точки — одна на весь дашборд (экран «Устройства», разворот строки на «Локациях», секция «Точка узла»
 * на «Узлах»): состояние (связь, что на экране и что должно быть, ошибка, батарея, прошивка), полный набор команд (проверить
 * связь, тест, подсветка, перезагрузка, изменить, секрет, удалить), привязка к узлу (или выбор свободного, если точка ничья)
 * и звук (что играет, фон, ход объявления). Раньше это были три разных места с разным набором возможностей — слияние убирает
 * расхождение (полная карточка была только на «Локациях», в карточке узла — урезанная копия).
 */
export function DeviceDetail({
  display: d,
  groups,
  channels,
  nodes,
  takenNodes,
  onChanged,
  onEdit,
  onSecret,
}: {
  display: DisplayItem;
  groups: DisplayGroup[];
  channels: AudioChannel[];
  /** Узлы (контейнеры) для привязки. */
  nodes: { id: string; name: string }[];
  /** Узел → id точки, которая на нём стоит (занятые недоступны в выборе). */
  takenNodes: Map<string, string>;
  onChanged: () => void;
  onEdit: () => void;
  onSecret: (r: DisplaySecretResponse) => void;
}) {
  const [level, setLevel] = useState("MEDIUM");
  const [confirm, setConfirm] = useState<Confirm | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [push, setPush] = useState<{ source: DisplaySource; title: string } | null>(null);
  const [nodeChoice, setNodeChoice] = useState("");
  const action = useAsyncAction({ fallbackError: "дисплей не ответил" });
  const base = `/api/displays/${encodeURIComponent(d.id)}`;
  const inFlight = d.push && d.push.version === d.desiredVersion && d.push.phase !== "DISPLAYED" ? d.push : null;
  const boundNodeName = d.nodeId ? nodes.find((n) => n.id === d.nodeId)?.name ?? d.nodeId : null;
  const freeNodes = nodes.filter((n) => !takenNodes.has(n.id) || takenNodes.get(n.id) === d.id);

  async function command(path: string, body: Record<string, unknown>, done: string) {
    setNote(null);
    const res = await action.run(() => api.post<{ ok: boolean; error?: string }>(`${base}/${path}`, body));
    if (res.ok) setNote(res.value.ok ? done : `не вышло: ${res.value.error ?? "нет ответа"}`);
    onChanged();
  }

  async function moveToGroup(groupId: string) {
    setNote(null);
    const res = await action.run(() => api.put<DisplayItem>(`${base}/group`, { groupId: groupId || null }));
    if (res.ok) onChanged();
  }

  async function bindNode(nodeId: string | null) {
    setNote(null);
    const res = await action.run(() => api.put<DisplayItem>(`${base}/node`, { nodeId }));
    if (res.ok) {
      setNodeChoice("");
      onChanged();
    }
  }

  async function resend() {
    const res = await action.run(() => api.get<DisplayPreview>(`${base}/preview`));
    if (res.ok) setPush({ source: { type: "qr", qr: res.value.qr, label: res.value.label }, title: res.value.label });
  }

  async function confirmed() {
    const what = confirm;
    setConfirm(null);
    if (what === "reboot") return command("reboot", {}, "перезагружается — через ~10 с снова на связи");
    if (what === "secret") {
      const res = await action.run(() => api.post<DisplaySecretResponse>(`${base}/secret`, {}));
      if (res.ok) onSecret(res.value);
    }
    if (what === "delete") {
      const res = await action.run(() => api.delete(base));
      if (res.ok) onChanged();
    }
  }

  const lagging = isLagging(d);

  return (
    <Panel className="display-card" title={<span className="mono">{d.id}</span>} action={<StatusAndBattery d={d} />}>
      <div className="display-card-sub">
        <span className="hint-text">{d.name}</span>
        {groups.length > 0 && (
          <AppSelect value={d.groupId ?? ""} onChange={(e) => moveToGroup(e.target.value)} disabled={action.busy} aria-label={`группа ${d.id}`}>
            <option value="">без группы</option>
            {groups.map((g) => (
              <option key={g.id} value={g.id}>
                {g.name}
              </option>
            ))}
          </AppSelect>
        )}
        {boundNodeName ? (
          <button type="button" className="link-button" onClick={() => navigate("nodes", d.nodeId!)}>
            узел «{boundNodeName}»
          </button>
        ) : (
          <span className="hint-text">без узла — просто динамик в локации</span>
        )}
      </div>
      <DeviceFacts d={d} />
      {inFlight && (
        <div className="display-inflight">
          <PushSteps phase={inFlight.phase} failedAt={inFlight.failedAt} />
          {inFlight.phase !== "FAILED" && <span className="hint-text">{phaseText(inFlight)}</span>}
        </div>
      )}
      <div className="display-actions">
        {boundNodeName && (
          <AppButton onClick={() => setPush({ source: { type: "container", id: d.nodeId! }, title: boundNodeName })} disabled={!d.enabled}>
            На дисплей
          </AppButton>
        )}
        {lagging && (
          <AppButton variant="primary" onClick={resend} disabled={action.busy || !d.enabled}>
            Повторить
          </AppButton>
        )}
        <AppButton onClick={() => command("probe", {}, "на связи")} disabled={action.busy}>
          Проверить связь
        </AppButton>
        <AppButton onClick={() => command("test", { seconds: 30 }, "тестовый экран на 30 с")} disabled={action.busy || !d.enabled}>
          Тест
        </AppButton>
        <AppSelect value={level} onChange={(e) => setLevel(e.target.value)} aria-label="уровень подсветки">
          {BACKLIGHT.map((b) => (
            <option key={b.value} value={b.value}>
              {b.label}
            </option>
          ))}
        </AppSelect>
        <AppButton
          onClick={() =>
            command(
              "backlight",
              { level, seconds: level === "OFF" ? 0 : BACKLIGHT_SECONDS },
              level === "OFF" ? "подсветка выключена" : `подсветка на ${BACKLIGHT_SECONDS} с`,
            )
          }
          disabled={action.busy || !d.enabled}
        >
          Подсветка
        </AppButton>
        <AppButton onClick={() => setConfirm("reboot")} disabled={action.busy || !d.enabled}>
          Перезагрузить
        </AppButton>
        {boundNodeName ? (
          <AppButton onClick={() => bindNode(null)} disabled={action.busy}>
            Отвязать узел
          </AppButton>
        ) : (
          freeNodes.length > 0 && (
            <>
              <AppSelect value={nodeChoice} onChange={(e) => setNodeChoice(e.target.value)} aria-label={`узел для ${d.id}`}>
                <option value="">привязать к узлу…</option>
                {freeNodes.map((n) => (
                  <option key={n.id} value={n.id}>
                    {n.name}
                  </option>
                ))}
              </AppSelect>
              <AppButton onClick={() => bindNode(nodeChoice)} disabled={action.busy || !nodeChoice}>
                Привязать
              </AppButton>
            </>
          )
        )}
        <AppButton onClick={onEdit}>Изменить</AppButton>
        <AppButton onClick={() => setConfirm("secret")}>Новый секрет</AppButton>
        <AppButton variant="danger" onClick={() => setConfirm("delete")}>
          Удалить
        </AppButton>
      </div>
      {action.busy && <p className="hint-text">жду ответа дисплея…</p>}
      {note && <p className="hint-text">{note}</p>}
      {action.error && <div className="login-error">{action.error}</div>}
      {d.audio && <PointAudioBlock className="node-point-audio" point={d} channels={channels} onSaved={onChanged} />}
      {confirm && (
        <AppDialog
          title={CONFIRM[confirm].title}
          body={CONFIRM[confirm].body(d.id)}
          confirmText={CONFIRM[confirm].confirmText}
          confirmVariant="danger"
          onConfirm={confirmed}
          onCancel={() => setConfirm(null)}
        />
      )}
      {push && (
        <DisplayPushDialog
          source={push.source}
          title={push.title}
          preselect={[d.id]}
          onClose={() => {
            setPush(null);
            onChanged();
          }}
        />
      )}
    </Panel>
  );
}
