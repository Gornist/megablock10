const SESSION_KEY = "mb10_admin_session";

export interface Session {
  sessionToken: string;
  master: { id: string; name: string };
  expiresAt: number;
}

export function loadSession(): Session | null {
  try {
    const raw = localStorage.getItem(SESSION_KEY);
    if (!raw) return null;
    const session = JSON.parse(raw) as Session;
    if (session.expiresAt < Date.now()) {
      localStorage.removeItem(SESSION_KEY);
      return null;
    }
    return session;
  } catch {
    return null;
  }
}

export function saveSession(session: Session) {
  try {
    localStorage.setItem(SESSION_KEY, JSON.stringify(session));
  } catch {
    // localStorage недоступен (приватный режим и т.п.) — сессия просто не переживёт перезагрузку.
  }
}

export function clearSession() {
  try {
    localStorage.removeItem(SESSION_KEY);
  } catch {
    // см. saveSession
  }
}

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const session = loadSession();
  const headers: Record<string, string> = { ...(init?.headers as Record<string, string>) };
  if (session) headers.authorization = `Bearer ${session.sessionToken}`;
  if (init?.body) headers["content-type"] = "application/json";

  const res = await fetch(path, { ...init, headers });
  if (res.status === 401) {
    clearSession();
    window.location.reload();
    throw new ApiError(401, "сессия истекла");
  }
  const isJson = res.headers.get("content-type")?.includes("json");
  const body = isJson ? await res.json() : await res.text();
  if (!res.ok) {
    throw new ApiError(res.status, typeof body === "object" && body?.error ? body.error : String(body));
  }
  return body as T;
}

export const api = {
  get: <T>(path: string) => request<T>(path),
  post: <T>(path: string, body?: unknown) => request<T>(path, { method: "POST", body: body ? JSON.stringify(body) : undefined }),
};
