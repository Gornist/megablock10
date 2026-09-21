import type { TargetSelector } from "../../api/types";

export type BulkTarget = "selected" | "faction" | "all";
export type BulkMode = "add" | "set";

export interface BulkForm {
  target: BulkTarget;
  selectedKeys: string[];
  /** Фракция, выбранная фильтром списка. */
  factionFilter: string;
  field: string;
  mode: BulkMode;
  value: string;
  reason: string;
}

/**
 * Запрос массовой правки из значений формы. Фракция всегда «установить» (прибавлять к названию нечего); «готово к предпросмотру»
 * требует значение, основание и непустой круг адресатов. Чистая функция — проверяется тестами отдельно от экрана.
 */
export function buildBulkRequest(f: BulkForm) {
  const mode: BulkMode = f.field === "faction" ? "set" : f.mode;
  const selector: TargetSelector = f.target === "selected" ? { keys: f.selectedKeys } : f.target === "faction" ? { faction: f.factionFilter } : { all: true };
  const request = { ...selector, field: f.field, newValue: f.value, mode, reason: f.reason };
  const hasTargets = !(f.target === "selected" && f.selectedKeys.length === 0) && !(f.target === "faction" && !f.factionFilter);
  return { request, mode, ready: f.value.trim() !== "" && f.reason.trim() !== "" && hasTargets };
}

/** Кого выбирать по умолчанию: выбранных галочками, иначе фракцию из фильтра, иначе всех. */
export function defaultTarget(selectedCount: number, factionFilter: string): BulkTarget {
  return selectedCount > 0 ? "selected" : factionFilter ? "faction" : "all";
}
