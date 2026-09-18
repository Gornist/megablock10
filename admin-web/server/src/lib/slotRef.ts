/**
 * slotRef — "containerId#slotIndex". В тексте ТЗ (§2.3/2.4) написано через
 * ':', но реальный формат в Android-клиенте — '#' (см. Container.slotRef и
 * комментарий там же: ':' конфликтует с тем, во что slotRef сам попадает).
 * Код — источник истины, не текст документа.
 */
export function containerIdOf(slotRef: string): string {
  const idx = slotRef.lastIndexOf("#");
  return idx === -1 ? slotRef : slotRef.slice(0, idx);
}

export function makeSlotRef(containerId: string, index: number): string {
  return `${containerId}#${index}`;
}
