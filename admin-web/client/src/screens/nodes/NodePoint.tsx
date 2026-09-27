import { useState } from "react";
import { api } from "../../api/client";
import type { AudioChannel, DisplayGroup, DisplayItem, DisplayPreview } from "../../api/types";
import { POLL_LIVE_MS, POLL_RELAXED_MS } from "../../api/pollIntervals";
import { useApiData } from "../../api/useApiData";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppSelect, Badge } from "../../design/components";
import { formatAgo } from "../../format";
import { navigate } from "../../router";
import { PointAnnounce, PointAudioControls, PointAudioStatus } from "../audio/PointAudio";
import { BatteryGauge } from "../displays/BatteryGauge";
import { DisplayMock, PushSteps } from "../displays/DisplayMock";
import { DisplayPushDialog } from "../displays/DisplayPushDialog";
import { phaseText, screenState, STATUS_LABEL, STATUS_TONE, type DisplaySource } from "../displays/displayUtil";
import { isLagging, useDisplayFrame } from "../displays/useDisplayFrame";

/**
 * Точка узла — узел-контейнер в мире и есть QR-дисплей со звуком (владелец). Секция карточки узла: что на экране, связь и
 * батарея, «На дисплей» / «Повторить», фон точки и ход объявления. Узел без точки — «Привязать точку» из непривязанных.
 * Команды обслуживания точки (тест, подсветка, секрет, удаление) — на экране «Локации».
 */
export function NodePoint({ nodeId, nodeName }: { nodeId: string; nodeName: string }) {
  const { data: displays, reload } = useApiData<DisplayItem[]>("/api/displays", { pollMs: POLL_LIVE_MS });
  const { data: groups } = useApiData<DisplayGroup[]>("/api/display-groups", { pollMs: POLL_RELAXED_MS });
  const { data: channels } = useApiData<AudioChannel[]>("/api/audio/channels", { pollMs: POLL_RELAXED_MS });
  const point = (displays ?? []).find((d) => d.nodeId === nodeId);
  if (!displays) return null;
  return (
    <section className="node-point" aria-label="точка узла">
      <div className="status-caps sound-step">Точка</div>
      {point ? (
        <BoundPoint point={point} nodeName={nodeName} groups={groups ?? []} channels={channels ?? []} onChanged={reload} />
      ) : (
        <BindPoint nodeId={nodeId} free={displays.filter((d) => !d.nodeId)} onChanged={reload} />
      )}
    </section>
  );
}

function BindPoint({ nodeId, free, onChanged }: { nodeId: string; free: DisplayItem[]; onChanged: () => void }) {
  const [choice, setChoice] = useState("");
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось привязать" });
  async function bind() {
    const r = await run(() => api.put(`/api/displays/${encodeURIComponent(choice)}/node`, { nodeId }));
    if (r.ok) onChanged();
  }
  return (
    <div className="node-point-empty">
      <p className="hint-text">У узла нет точки — QR только на бумаге, звука нет.</p>
      {free.length === 0 ? (
        <p className="hint-text">Свободных точек нет — добавьте на экране «Локации».</p>
      ) : (
        <div className="display-actions">
          <AppSelect value={choice} onChange={(e) => setChoice(e.target.value)} aria-label="точка для узла">
            <option value="">выберите точку…</option>
            {free.map((d) => (
              <option key={d.id} value={d.id}>
                {d.name} ({d.id})
              </option>
            ))}
          </AppSelect>
          <AppButton variant="primary" onClick={bind} disabled={busy || !choice}>
            Привязать точку
          </AppButton>
        </div>
      )}
      {error && <div className="login-error">{error}</div>}
    </div>
  );
}

function BoundPoint({
  point: d,
  nodeName,
  groups,
  channels,
  onChanged,
}: {
  point: DisplayItem;
  nodeName: string;
  groups: DisplayGroup[];
  channels: AudioChannel[];
  onChanged: () => void;
}) {
  const framePng = useDisplayFrame(d);
  const [push, setPush] = useState<{ source: DisplaySource; title: string } | null>(null);
  const action = useAsyncAction({ fallbackError: "не удалось" });
  const shownState = screenState(d);
  const inFlight = d.push && d.push.version === d.desiredVersion && d.push.phase !== "DISPLAYED" ? d.push : null;
  const group = groups.find((g) => g.id === d.groupId);

  async function resend() {
    const res = await action.run(() => api.get<DisplayPreview>(`/api/displays/${encodeURIComponent(d.id)}/preview`));
    if (res.ok) setPush({ source: { type: "qr", qr: res.value.qr, label: res.value.label }, title: res.value.label });
  }
  async function unbind() {
    const res = await action.run(() => api.put(`/api/displays/${encodeURIComponent(d.id)}/node`, { nodeId: null }));
    if (res.ok) onChanged();
  }

  return (
    <div className="node-point-body" data-point={d.id}>
      <div className="node-point-head">
        <span>
          <span className="sound-point-name">{d.name}</span> <span className="hint-text mono">{d.id}</span>
          {" · "}
          <button type="button" className="link-button" onClick={() => navigate("locations")}>
            {group ? `локация «${group.name}»` : "без локации"}
          </button>
        </span>
        <span className="display-card-status">
          <Badge tone={STATUS_TONE[d.status]}>{STATUS_LABEL[d.status]}</Badge>
          <BatteryGauge d={d} />
        </span>
      </div>
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
          <dt>на связи</dt>
          <dd>{formatAgo(d.lastSeenAt)}</dd>
          <dt>на экране</dt>
          <dd>
            {d.displayedVersion ? `v${d.displayedVersion}` : "—"}
            {d.desiredLabel && d.displayedVersion === d.desiredVersion ? ` · ${d.desiredLabel}` : ""}
          </dd>
          {d.lastError && (
            <>
              <dt>ошибка</dt>
              <dd className="login-error">
                {d.lastError} ({formatAgo(d.lastErrorAt)})
              </dd>
            </>
          )}
        </dl>
      </div>
      {inFlight && (
        <div className="display-inflight">
          <PushSteps phase={inFlight.phase} failedAt={inFlight.failedAt} />
          {inFlight.phase !== "FAILED" && <span className="hint-text">{phaseText(inFlight)}</span>}
        </div>
      )}
      <div className="display-actions">
        <AppButton onClick={() => setPush({ source: { type: "container", id: d.nodeId! }, title: nodeName })} disabled={!d.enabled}>
          На дисплей
        </AppButton>
        {isLagging(d) && (
          <AppButton variant="primary" onClick={resend} disabled={action.busy || !d.enabled}>
            Повторить
          </AppButton>
        )}
        <AppButton onClick={unbind} disabled={action.busy}>
          Отвязать
        </AppButton>
      </div>
      {d.audio && (
        <div className="node-point-audio">
          <PointAudioStatus point={d} />
          <PointAudioControls point={d} channels={channels} onSaved={onChanged} />
          <PointAnnounce point={d} />
        </div>
      )}
      {action.error && <div className="login-error">{action.error}</div>}
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
    </div>
  );
}

/** Значки точки в списке узлов: на связи ли, батарея, звук. Нет точки — прочерк. */
export function PointBadges({ point }: { point: DisplayItem | undefined }) {
  if (!point) return <span className="hint-text">—</span>;
  return (
    <span className="point-badges" data-point={point.id}>
      <Badge tone={STATUS_TONE[point.status]}>{STATUS_LABEL[point.status]}</Badge>
      {point.batteryPct !== null && (
        <span className={`hint-text mono${point.battery === "CRITICAL" ? " login-error" : ""}`} title="батарея">
          {point.batteryPct}%
        </span>
      )}
      {point.audio && <span title="звуковая точка">♪</span>}
    </span>
  );
}
