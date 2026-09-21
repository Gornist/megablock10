import type { ProvisionItem } from "../../api/types";

export const RAM_OPTIONS = [0, 6, 7, 8, 9, 10, 11, 12, 13];
export const ramLabel = (r: number) => (r === 0 ? "по умолчанию" : String(r));

export function provisionStatus(p: ProvisionItem): { label: string; tone: "ok" | "danger" | "accent" | "neutral" } {
  if (p.conflicts > 0) return { label: "применён дважды!", tone: "danger" };
  if (p.boundKey) return { label: p.void ? `применён · ${p.boundName}, перевыдан` : `применён · ${p.boundName}`, tone: p.void ? "neutral" : "ok" };
  if (p.void) return { label: "погашен", tone: "neutral" };
  return { label: "ждёт игрока", tone: "accent" };
}
