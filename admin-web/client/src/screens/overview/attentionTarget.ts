import type { AttentionItem } from "../../api/types";
import { navigate } from "../../router";

/**
 * Куда ведёт тревога: тревога аудитора Сети → экран «Сеть»; игрок → его карточка; узел → карточка узла (и точка, стоящая узлом, —
 * туда же: там её карточка); точка без узла → её карточка в «Устройствах». Ничего из этого — тревога без ссылки.
 */
export function attentionTarget(i: Pick<AttentionItem, "subjectKey" | "nodeId" | "displayId"> & { kind?: AttentionItem["kind"] }): (() => void) | undefined {
  if (i.kind === "net_alert" || i.kind === "net_master_alert") return () => navigate("net");
  if (i.subjectKey) return () => navigate("players", i.subjectKey!);
  if (i.nodeId) return () => navigate("nodes", i.nodeId!);
  if (i.displayId) return () => navigate("devices", i.displayId!);
  return undefined;
}
