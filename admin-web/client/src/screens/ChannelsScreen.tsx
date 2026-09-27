import type { AudioCatalogTrack, AudioChannel, DisplayGroup, DisplayItem } from "../api/types";
import { useApiData } from "../api/useApiData";
import { POLL_LIVE_MS, POLL_RELAXED_MS } from "../api/pollIntervals";
import { ChannelsPanel } from "./audio/ChannelsPanel";
import { isAudioPoint } from "./audio/audioUtil";

/**
 * Каналы звука — плейлисты фона с карт точек. Что где играет, назначается в «Локациях» (канал локации) и в карточке узла
 * (исключение точки); здесь — сами плейлисты и кто их слушает.
 */
export function ChannelsScreen() {
  const { data: displays, reload } = useApiData<DisplayItem[]>("/api/displays", { pollMs: POLL_LIVE_MS });
  const { data: groups, reload: reloadGroups } = useApiData<DisplayGroup[]>("/api/display-groups", { pollMs: POLL_RELAXED_MS });
  const { data: channels, reload: reloadChannels } = useApiData<AudioChannel[]>("/api/audio/channels", { pollMs: POLL_RELAXED_MS });
  const { data: catalog } = useApiData<AudioCatalogTrack[]>("/api/audio/catalog", { pollMs: POLL_RELAXED_MS });
  const reloadAll = () => {
    reload();
    reloadGroups();
    reloadChannels();
  };
  return (
    <div className="screen-grid">
      <p className="hint-text master-intro">
        Канал — список треков с карт точек (/mb10/tracks). Назначьте его локации — и вся локация заиграет; отдельной точке — в карточке узла или в «Локациях».
      </p>
      <ChannelsPanel
        channels={channels ?? []}
        catalog={catalog ?? []}
        groups={groups ?? []}
        points={(displays ?? []).filter(isAudioPoint)}
        onChanged={reloadAll}
      />
    </div>
  );
}
