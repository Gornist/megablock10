import type { DisplayItem } from "../../api/types";
import { formatAgo } from "../../format";
import { DisplayMock } from "./DisplayMock";
import { screenState } from "./displayUtil";
import { useDisplayFrame } from "./useDisplayFrame";

/**
 * Что сейчас на точке — тело карточки `DeviceDetail`: макет панели с кадром последней отправки и отметкой
 * («на экране / передаётся / загружено / ошибка») и факты: адрес, когда была на связи, что на экране и что должно быть,
 * последняя ошибка, прошивка, размер панели.
 */
export function DeviceFacts({ d }: { d: DisplayItem }) {
  const framePng = useDisplayFrame(d);
  const shownState = screenState(d);
  return (
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
  );
}
