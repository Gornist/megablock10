import type { DisplayGroup, DisplayItem } from "../../api/types";
import { isOnline } from "../displays/displayUtil";
import type { AnnounceTargetsState, TargetMode } from "./useAnnounceTargets";

const MODES = (points: DisplayItem[]): (readonly [TargetMode, string])[] => [
  ["all", `все точки (${points.length})`],
  ["groups", "группы"],
  ["points", "отдельные точки"],
];

/** Шаг «2 · где» громкой связи: кому объявлять — все, отмеченные локации (только те, где есть звуковые точки) или точки. */
export function AnnounceTargets({ t, groups, points }: { t: AnnounceTargetsState; groups: DisplayGroup[]; points: DisplayItem[] }) {
  const groupsWithAudio = groups.filter((g) => points.some((p) => p.groupId === g.id));
  return (
    <>
      <div className="sound-target-modes" role="radiogroup" aria-label="кому">
        {MODES(points).map(([m, label]) => (
          <label key={m} className="sound-check">
            <input type="radio" name="announce-mode" checked={t.mode === m} onChange={() => t.setMode(m)} /> {label}
          </label>
        ))}
      </div>
      {t.mode === "groups" && (
        <div className="sound-checklist">
          {groupsWithAudio.length === 0 && <span className="hint-text">в группах нет звуковых точек</span>}
          {groupsWithAudio.map((g) => (
            <label key={g.id} className="sound-check">
              <input type="checkbox" checked={t.groupIds.has(g.id)} onChange={() => t.toggleGroup(g.id)} /> {g.name}
              <span className="hint-text"> · {points.filter((p) => p.groupId === g.id).length}</span>
            </label>
          ))}
        </div>
      )}
      {t.mode === "points" && (
        <div className="sound-checklist">
          {points.map((p) => (
            <label key={p.id} className="sound-check">
              <input type="checkbox" checked={t.pointIds.has(p.id)} onChange={() => t.togglePoint(p.id)} /> {p.name}
              {!isOnline(p) && <span className="hint-text"> · нет связи</span>}
            </label>
          ))}
        </div>
      )}
    </>
  );
}
