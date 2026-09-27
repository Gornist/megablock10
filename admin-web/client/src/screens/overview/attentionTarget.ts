import type { AttentionItem } from "../../api/types";
import { navigate } from "../../router";

/**
 * Куда ведёт тревога: игрок → его карточка; узел → карточка узла (и точка, стоящая узлом, — туда же); точка без узла →
 * «Локации». Ничего из этого — тревога без ссылки.
 */
export function attentionTarget(i: Pick<AttentionItem, "subjectKey" | "nodeId" | "displayId">): (() => void) | undefined {
  if (i.subjectKey) return () => navigate("players", i.subjectKey!);
  if (i.nodeId) return () => navigate("nodes", i.nodeId!);
  if (i.displayId) return () => navigate("locations");
  return undefined;
}
