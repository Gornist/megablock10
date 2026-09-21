import { vi } from "vitest";
import { api } from "../api/client";

type Handler = unknown | ((body?: unknown) => unknown);

/**
 * Подменяет api.get/post/put/delete таблицей «метод + путь → ответ» (значение или функция от тела). Неизвестный путь роняет тест понятной
 * ошибкой, чтобы экран не молча ходил «в сеть». Вызывать после vi.mock("../api/client") в самом тесте.
 */
export function mockApi(routes: Record<string, Handler>) {
  const calls: { method: string; path: string; body?: unknown }[] = [];
  const respond = (method: string) => async (path: string, body?: unknown) => {
    calls.push({ method, path, body });
    const key = `${method} ${path}`;
    if (!(key in routes)) throw new Error(`mockApi: нет маршрута ${key}`);
    const h = routes[key];
    return typeof h === "function" ? (h as (b?: unknown) => unknown)(body) : h;
  };
  vi.mocked(api.get).mockImplementation(respond("GET") as never);
  vi.mocked(api.post).mockImplementation(respond("POST") as never);
  vi.mocked(api.put).mockImplementation(respond("PUT") as never);
  vi.mocked(api.delete).mockImplementation(respond("DELETE") as never);
  return calls;
}
