import type { CharacterSnapshot } from "../../api/types";
import { formatAgo } from "../../format";
import { navigate } from "../../router";

/** Плашки о судьбе сессии игрока: сброшена на телефоне, перевыдана на другой телефон, выдана после прежней. */
export function PlayerBanners({ snapshot }: { snapshot: CharacterSnapshot }) {
  return (
    <>
      {snapshot.sessionResetAt !== null && !snapshot.replacedBy && (
        <div className="asof-banner">
          Сессия сброшена на телефоне {formatAgo(snapshot.sessionResetAt)}: устройство свободно, персонаж сохранён — нажмите «Выдать заново». В сводках этот игрок не считается.
        </div>
      )}
      {snapshot.replacedBy && (
        <div className="asof-banner">
          Персонаж перевыдан на другой телефон, эта сессия закрыта и в сводках не считается.{" "}
          <button type="button" className="change-toggle" onClick={() => navigate("players", snapshot.replacedBy!)}>
            открыть текущую сессию →
          </button>
        </div>
      )}
      {snapshot.replaces && (
        <div className="asof-banner">
          Персонаж выдан заново после прежней сессии.{" "}
          <button type="button" className="change-toggle" onClick={() => navigate("players", snapshot.replaces!)}>
            открыть предыдущую сессию (история) →
          </button>
        </div>
      )}
    </>
  );
}
