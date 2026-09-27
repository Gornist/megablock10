import { useEffect, useState } from "react";
import { api } from "../../api/client";
import type { DisplayItem, DisplayPreview, DisplaySecretResponse } from "../../api/types";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppDialog, AppSelect, Badge, Panel } from "../../design/components";
import { formatAgo } from "../../format";
import { DisplayMock, PushSteps } from "./DisplayMock";
import { phaseText, screenState, STATUS_LABEL, STATUS_TONE, type DisplaySource } from "./displayUtil";

const BACKLIGHT = [
  { value: "OFF", label: "выкл" },
  { value: "LOW", label: "слабо" },
  { value: "MEDIUM", label: "средне" },
  { value: "HIGH", label: "ярко" },
];
/** Подсветка из дашборда — для проверки на месте; гаснет сама, чтобы не посадить батарею забытой командой. */
const BACKLIGHT_SECONDS = 20;

const BATTERY_TONE = { OK: "ok", LOW: "warn", CRITICAL: "danger" } as const;

type Confirm = "reboot" | "secret" | "delete";

/**
 * Карточка дисплея: состояние (связь, что на экране и что должно быть, последняя ошибка, батарея), команды (проверить связь, тест,
 * подсветка, перезагрузка) и управление записью. «Повторить» досылает то, что должно быть на экране, если прошлая отправка не дошла.
 */
export function DisplayCard({
  display: d,
  onChanged,
  onEdit,
  onSecret,
  onPush,
}: {
  display: DisplayItem;
  onChanged: () => void;
  onEdit: () => void;
  onSecret: (r: DisplaySecretResponse) => void;
  onPush: (source: DisplaySource, title: string) => void;
}) {
  const [level, setLevel] = useState("MEDIUM");
  const [confirm, setConfirm] = useState<Confirm | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const action = useAsyncAction({ fallbackError: "дисплей не ответил" });
  const base = `/api/displays/${encodeURIComponent(d.id)}`;
  // Кадр последней отправки — для макета «что на экране»; сервер перерисовывает его при каждой новой версии. Хранится вместе с
  // версией: пока не пришёл кадр новой версии, старый не показывается. Причина ошибки — в «ошибка» выше, под шкалой не повторяется.
  const [frame, setFrame] = useState<{ version: number; preview: DisplayPreview } | null>(null);
  useEffect(() => {
    const version = d.desiredVersion;
    if (version === null) return;
    let cancelled = false;
    api
      .get<DisplayPreview>(`${base}/preview`)
      .then((preview) => !cancelled && setFrame({ version, preview }))
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [base, d.desiredVersion]);
  const framePng = frame && frame.version === d.desiredVersion ? frame.preview.png : null;
  const shownState = screenState(d);
  const inFlight = d.push && d.push.version === d.desiredVersion && d.push.phase !== "DISPLAYED" ? d.push : null;

  async function command(path: string, body: Record<string, unknown>, done: string) {
    setNote(null);
    const res = await action.run(() => api.post<{ ok: boolean; error?: string }>(`${base}/${path}`, body));
    if (res.ok) setNote(res.value.ok ? done : `не вышло: ${res.value.error ?? "нет ответа"}`);
    onChanged();
  }

  async function resend() {
    const res = await action.run(() => api.get<DisplayPreview>(`${base}/preview`));
    if (res.ok) onPush({ type: "qr", qr: res.value.qr, label: res.value.label }, res.value.label);
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

  const lagging = d.desiredVersion !== null && (d.displayedVersion ?? 0) < d.desiredVersion && d.activeVersion === null && d.pendingVersion === null;

  return (
    <Panel
      title={
        <span className="display-card-head">
          <span className="mono">{d.id}</span>
          <Badge tone={STATUS_TONE[d.status]}>{STATUS_LABEL[d.status]}</Badge>
          {d.battery && <Badge tone={BATTERY_TONE[d.battery]}>{((d.batteryMv ?? 0) / 1000).toFixed(2)} В</Badge>}
        </span>
      }
    >
      <div className="hint-text">{d.name}</div>
      <div className={`display-card-body${d.width > d.height ? " landscape" : ""}`}>
        {shownState && (
          <DisplayMock
            png={framePng}
            width={d.width}
            height={d.height}
            state={shownState}
            note={shownState === "shown" ? `v${d.displayedVersion}` : d.displayedVersion ? `на экране пока v${d.displayedVersion}` : undefined}
          />
        )}
        <dl className="display-facts">
          <dt>адрес</dt>
          <dd className="mono">
            {d.ip}:{d.port}
          </dd>
          <dt>на связи</dt>
          <dd>{formatAgo(d.lastSeenAt)}</dd>
          <dt>на экране</dt>
          <dd>
            {d.displayedVersion ? `v${d.displayedVersion}` : "—"}
            {d.desiredLabel && d.displayedVersion === d.desiredVersion ? ` · ${d.desiredLabel}` : ""}
            {d.displayedAt ? ` · ${formatAgo(d.displayedAt)}` : ""}
          </dd>
          {d.desiredVersion !== null && d.desiredVersion !== d.displayedVersion && (
            <>
              <dt>должно быть</dt>
              <dd>
                v{d.desiredVersion} · {d.desiredLabel}
                {d.activeVersion !== null ? " · отправляется" : d.pendingVersion !== null ? " · в очереди" : " · не дошло"}
              </dd>
            </>
          )}
          {d.lastError && (
            <>
              <dt>ошибка</dt>
              <dd className="login-error">
                {d.lastError} ({formatAgo(d.lastErrorAt)})
              </dd>
            </>
          )}
          <dt>прошивка</dt>
          <dd className="mono">
            {d.fwVersion ?? "—"}
            {d.rssi !== null ? ` · Wi-Fi ${d.rssi} дБм` : ""}
            {d.hardwareId ? ` · ${d.hardwareId}` : ""}
          </dd>
          <dt>панель</dt>
          <dd className="mono">
            {d.width}×{d.height}
          </dd>
        </dl>
      </div>
      {inFlight && (
        <div className="display-inflight">
          <PushSteps phase={inFlight.phase} failedAt={inFlight.failedAt} />
          {inFlight.phase !== "FAILED" && <span className="hint-text">{phaseText(inFlight)}</span>}
        </div>
      )}
      <div className="display-actions">
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
        <AppButton onClick={onEdit}>Изменить</AppButton>
        <AppButton onClick={() => setConfirm("secret")}>Новый секрет</AppButton>
        <AppButton variant="danger" onClick={() => setConfirm("delete")}>
          Удалить
        </AppButton>
      </div>
      {action.busy && <p className="hint-text">жду ответа дисплея…</p>}
      {note && <p className="hint-text">{note}</p>}
      {action.error && <div className="login-error">{action.error}</div>}
      {confirm && (
        <AppDialog
          title={confirm === "reboot" ? "Перезагрузить дисплей?" : confirm === "secret" ? "Сменить секрет?" : "Удалить дисплей?"}
          body={
            confirm === "reboot"
              ? `${d.id} перезагрузится и восстановит последний кадр.`
              : confirm === "secret"
                ? `Старый секрет перестанет работать: ${d.id} придётся прошить новым, до этого он не примет ни одной картинки.`
                : `${d.id} пропадёт из списка; на панели останется последний кадр.`
          }
          confirmText={confirm === "reboot" ? "Перезагрузить" : confirm === "secret" ? "Сменить" : "Удалить"}
          confirmVariant="danger"
          onConfirm={confirmed}
          onCancel={() => setConfirm(null)}
        />
      )}
    </Panel>
  );
}
