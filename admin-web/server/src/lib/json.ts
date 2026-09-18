/** Было продублировано в routes/overview.ts и routes/nodes.ts дословно — один разбор JSON из new_value на оба места. */
export function parseSafe<T>(text: string | null): T | null {
  if (!text) return null;
  try {
    return JSON.parse(text) as T;
  } catch {
    return null;
  }
}
