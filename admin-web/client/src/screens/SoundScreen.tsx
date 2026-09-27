import type { AudioCatalogTrack, AudioChannel, AudioClip, DisplayGroup, DisplayItem } from "../api/types";
import { useApiData } from "../api/useApiData";
import { POLL_LIVE_MS, POLL_RELAXED_MS } from "../api/pollIntervals";
import { AsyncPanel } from "../design/AsyncPanel";
import { Panel, StatTile } from "../design/components";
import { AnnouncePanel } from "./audio/AnnouncePanel";
import { ChannelsPanel } from "./audio/ChannelsPanel";
import { LocationsPanel } from "./audio/LocationsPanel";
import { announceActive, isAudioPoint, isOnline } from "./audio/audioUtil";

/**
 * Звук площадки (docs/sound-nodes.md): те же точки, что показывают QR, играют фон локации с карты памяти и объявления
 * громкой связи. Сверху — громкая связь (на игре она нужна срочно), ниже — что где играет, внизу — каналы.
 */
export function SoundScreen() {
  const { data: displays, error, reload } = useApiData<DisplayItem[]>("/api/displays", { pollMs: POLL_LIVE_MS });
  const { data: groups, reload: reloadGroups } = useApiData<DisplayGroup[]>("/api/display-groups", { pollMs: POLL_LIVE_MS });
  const { data: channels, reload: reloadChannels } = useApiData<AudioChannel[]>("/api/audio/channels", { pollMs: POLL_RELAXED_MS });
  const { data: catalog } = useApiData<AudioCatalogTrack[]>("/api/audio/catalog", { pollMs: POLL_RELAXED_MS });
  const { data: clips, reload: reloadClips } = useApiData<AudioClip[]>("/api/audio/clips", { pollMs: false });

  const points = (displays ?? []).filter(isAudioPoint);
  const online = points.filter(isOnline);
  const reloadAll = () => {
    reload();
    reloadGroups();
    reloadChannels();
  };

  return (
    <div className="screen-grid">
      <p className="hint-text master-intro">
        Звуковые точки — дисплеи со звуковой платой: играют фон своей локации с карты памяти и объявления громкой связи. Фон меняется здесь за секунды; точка
        без связи доиграет старый и переключится, как только вернётся в сеть.
      </p>
      <div className="stat-row">
        <StatTile label="звуковых точек" value={points.length} />
        <StatTile label="на связи" value={online.length} tone="ok" />
        <StatTile label="фон применён" value={online.filter((p) => p.audio!.applied).length} tone="accent" />
        <StatTile label="идёт объявление" value={points.filter((p) => announceActive(p.audio!.announce)).length} tone="money" />
      </div>
      <AsyncPanel data={displays} error={error} isEmpty={() => points.length === 0} emptyLabel="звуковых точек пока нет">
        {() => (
          <>
            <AnnouncePanel clips={clips ?? []} groups={groups ?? []} points={points} onClipsChanged={reloadClips} onAnnounced={reload} />
            <LocationsPanel groups={groups ?? []} points={points} channels={channels ?? []} onChanged={reloadAll} />
          </>
        )}
      </AsyncPanel>
      {displays && points.length === 0 && (
        <Panel title="Как появляется звуковая точка">
          <p className="hint-text">
            Добавьте точку на экране «Дисплеи». Если на ней стоит звуковая плата (MAX98357A + microSD, docs/sound-nodes.md), прошивка сообщит об этом при первом
            соединении — и точка появится здесь.
          </p>
        </Panel>
      )}
      <ChannelsPanel channels={channels ?? []} catalog={catalog ?? []} groups={groups ?? []} points={points} onChanged={reloadAll} />
    </div>
  );
}
