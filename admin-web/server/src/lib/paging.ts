/** Разбор постраничной выдачи (`?page=&pageSize=`): раньше одна и та же пара строк жила в audit, events и players. Страницы с нуля, размер 1…maxSize. */
export function parsePaging(query: { page?: string; pageSize?: string }, defaultSize = 50, maxSize = 200): { page: number; pageSize: number } {
  return {
    page: Math.max(0, Number(query.page) || 0),
    pageSize: Math.min(maxSize, Math.max(1, Number(query.pageSize) || defaultSize)),
  };
}
