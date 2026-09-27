import { useEffect, useState } from "react";
import { api } from "../../api/client";
import type { DisplayItem, DisplayPreview } from "../../api/types";

/**
 * Кадр последней отправки — для макета «что на экране»; сервер перерисовывает его при каждой новой версии. Хранится вместе с
 * версией: пока не пришёл кадр новой версии, старый не показывается (null). Общее у карточки дисплея и точки в карточке узла.
 */
export function useDisplayFrame(d: DisplayItem): string | null {
  const [frame, setFrame] = useState<{ version: number; preview: DisplayPreview } | null>(null);
  const base = `/api/displays/${encodeURIComponent(d.id)}`;
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
  return frame && frame.version === d.desiredVersion ? frame.preview.png : null;
}

/** Должна показывать новее, чем показывает, и ничего не в пути — нужна кнопка «Повторить». */
export function isLagging(d: DisplayItem): boolean {
  return d.desiredVersion !== null && (d.displayedVersion ?? 0) < d.desiredVersion && d.activeVersion === null && d.pendingVersion === null;
}
