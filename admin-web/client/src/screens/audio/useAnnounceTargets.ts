import { useState } from "react";
import type { DisplayItem } from "../../api/types";

export type TargetMode = "all" | "groups" | "points";

const toggled = (set: Set<string>, id: string) => {
  const next = new Set(set);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  return next;
};

/**
 * «Где услышат» объявление: все точки, отмеченные локации или отдельные точки. `targets` — тело для сервера
 * (`/api/audio/announce` и `…/stop`), `targetCount` — сколько точек его получат (для кнопки «объявить → N»).
 */
export function useAnnounceTargets(points: DisplayItem[]) {
  const [mode, setMode] = useState<TargetMode>("all");
  const [groupIds, setGroupIds] = useState<Set<string>>(new Set());
  const [pointIds, setPointIds] = useState<Set<string>>(new Set());
  const targets = mode === "all" ? { all: true } : mode === "groups" ? { groupIds: [...groupIds] } : { displayIds: [...pointIds] };
  const targetCount = mode === "all" ? points.length : mode === "groups" ? points.filter((p) => p.groupId && groupIds.has(p.groupId)).length : pointIds.size;
  return {
    mode,
    setMode,
    groupIds,
    pointIds,
    toggleGroup: (id: string) => setGroupIds((s) => toggled(s, id)),
    togglePoint: (id: string) => setPointIds((s) => toggled(s, id)),
    targets,
    targetCount,
  };
}

export type AnnounceTargetsState = ReturnType<typeof useAnnounceTargets>;
