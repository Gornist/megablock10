import type { AudioClip, DisplayGroup, DisplayItem } from "../api/types";
import { useApiData } from "../api/useApiData";
import { POLL_LIVE_MS } from "../api/pollIntervals";
import { AsyncPanel } from "../design/AsyncPanel";
import { Panel, StatTile } from "../design/components";
import { AnnouncePanel } from "./audio/AnnouncePanel";
import { announceActive, isAudioPoint, isOnline } from "./audio/audioUtil";

/**
 * Громкая связь (docs/sound-nodes.md): записать объявление или взять заготовку, выбрать, где его услышат (все / локации /
 * точки), и видеть по каждой точке, дошло ли и доиграло ли. Кнопка — и в шапке меню: срочное объявление с любого экрана.
 */
export function AnnounceScreen() {
  const { data: displays, error, reload } = useApiData<DisplayItem[]>("/api/displays", { pollMs: POLL_LIVE_MS });
  const { data: groups } = useApiData<DisplayGroup[]>("/api/display-groups", { pollMs: POLL_LIVE_MS });
  const { data: clips, reload: reloadClips } = useApiData<AudioClip[]>("/api/audio/clips", { pollMs: false });

  const points = (displays ?? []).filter(isAudioPoint);
  const online = points.filter(isOnline);

  return (
    <div className="screen-grid">
      <div className="stat-row">
        <StatTile label="звуковых точек" value={points.length} />
        <StatTile label="на связи" value={online.length} tone="ok" />
        <StatTile label="идёт объявление" value={points.filter((p) => announceActive(p.audio!.announce)).length} tone="money" />
      </div>
      <AsyncPanel data={displays} error={error} isEmpty={() => points.length === 0} emptyLabel="звуковых точек пока нет">
        {() => <AnnouncePanel clips={clips ?? []} groups={groups ?? []} points={points} onClipsChanged={reloadClips} onAnnounced={reload} />}
      </AsyncPanel>
      {displays && points.length === 0 && (
        <Panel title="Как появляется звуковая точка">
          <p className="hint-text">
            Добавьте точку на экране «Локации» с галочкой «со звуком» в строке настройки платы. Если на ней стоит звуковая плата (MAX98357A + microSD,
            docs/sound-nodes.md), прошивка сообщит об этом при первом соединении — и точка появится здесь.
          </p>
        </Panel>
      )}
    </div>
  );
}
