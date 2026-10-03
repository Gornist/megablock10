import type { AudioChannel, DisplayGroup, DisplayItem, NodeSummary } from "../../api/types";
import { POLL_LIVE_MS, POLL_RELAXED_MS } from "../../api/pollIntervals";
import { useApiData } from "../../api/useApiData";

/** Узел для выбора в карточке и форме точки — без лишних полей сводки. */
export interface NamedNode {
  id: string;
  name: string;
}

/** Узел → id точки, которая на нём стоит (одна точка — один узел; занятые недоступны в выборе). */
export function takenNodesOf(displays: DisplayItem[]): Map<string, string> {
  return new Map(displays.filter((d) => d.nodeId).map((d) => [d.nodeId!, d.id]));
}

/**
 * Всё, что нужно экрану с точками («Устройства», «Локации», точка узла): сами точки, локации, каналы звука, узлы — и
 * производные, которые раньше каждый экран считал сам (занятые узлы, узлы для выбора, имена). Точки опрашиваются часто
 * (связь и ход отправки видны сразу), остальное — реже; «Локациям» локации нужны чаще (фон в заголовке).
 */
export function useDeviceData({ groupsPollMs = POLL_RELAXED_MS }: { groupsPollMs?: number } = {}) {
  const { data: displays, error, reload } = useApiData<DisplayItem[]>("/api/displays", { pollMs: POLL_LIVE_MS });
  const { data: groups, reload: reloadGroups } = useApiData<DisplayGroup[]>("/api/display-groups", { pollMs: groupsPollMs });
  const { data: channels } = useApiData<AudioChannel[]>("/api/audio/channels", { pollMs: POLL_RELAXED_MS });
  const { data: nodes } = useApiData<NodeSummary[]>("/api/nodes", { pollMs: POLL_RELAXED_MS });
  const namedNodes: NamedNode[] = (nodes ?? []).map((n) => ({ id: n.id, name: n.name }));
  return {
    /** null — ещё не загружено (для AsyncPanel). */
    displays,
    error,
    groups: groups ?? [],
    channels: channels ?? [],
    namedNodes,
    nodeName: new Map(namedNodes.map((n) => [n.id, n.name])),
    takenNodes: takenNodesOf(displays ?? []),
    /** Только точки — после команды точке; локации не менялись. */
    reload,
    reloadGroups,
    /** Точки и локации — после правки точки (могла переехать в другую локацию). */
    reloadAll: () => {
      reload();
      reloadGroups();
    },
  };
}
