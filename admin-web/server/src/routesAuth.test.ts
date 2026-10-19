import { test } from "node:test";
import assert from "node:assert/strict";
import diagnostics_channel from "node:diagnostics_channel";
import type { FastifyInstance } from "fastify";
import { testApp, testDb } from "./testUtil.js";

/**
 * «Каждый маршрут закрыт»: `requireMaster` стоит в каждом обработчике вручную (≈110 вызовов), и забытый вызов целиком не ловит ни ревью по диффу,
 * ни поштучные тесты на 401. Здесь маршруты перечисляются из самого Fastify (хук onRoute на свежем экземпляре), и каждый без токена мастера
 * обязан ответить 401. Открытые маршруты — только в списке OPEN ниже, с причиной; новый маршрут без защиты и без записи в список роняет тест.
 */

/** Маршруты без токена мастера. Ключ — «МЕТОД путь» как в Fastify. Добавлять сюда — только осознанно: это дверь наружу. */
const OPEN: Record<string, string> = {
  "POST /api/auth/login": "вход мастера: сам выдаёт сессию",
  "POST /api/auth/logout": "идемпотентен, без токена ничего не делает",
  "GET /api/capabilities": "версии протокола для Моста и телефонов, без данных",
  "POST /api/changes": "приём записей от телефонов и Моста — по секрету игры и подписи записи, не по мастеру",
  "POST /api/provisions/redeem": "вход коротким кодом: телефон на первом запуске ещё ничего не знает; защита — redeemLimiter (5 неверных с IP → пауза, общий потолок)",
  "POST /api/slots/:slotRef/claim": "телефон забирает слот — по секрету игры и подписи ключа",
  "POST /api/world-events": "события мира от Моста — по секрету игры",
  "GET /api/health": "проверка живости, без данных",
};

/** Из открытых — те, что закрыты секретом игры: при заданном GAME_SECRET без заголовка отвечают 401. Проверяется отдельно ниже. */
const GAME_SECRET_ROUTES = new Set<string>([
  "POST /api/changes",
  "POST /api/slots/:slotRef/claim",
  "POST /api/world-events",
]);

/**
 * Маршруты Сети проверяют тело раньше мастера (400 вместо 401 на пустое тело), а само действие идёт через `act()` из netAct.ts, где
 * requireMaster первым делом. Отказ по форме без токена ничего не меняет и не раскрывает; главное — никакого 2xx без мастера.
 */
const BODY_FIRST = (r: Route) => r.url.startsWith("/api/net/") && r.method !== "GET";

interface Route { method: string; url: string }

/** Собирает все маршруты, зарегистрированные в buildApp: Fastify сообщает о новом экземпляре через diagnostics-канал до регистрации маршрутов. */
function collectRoutes(): { app: FastifyInstance; routes: Route[] } {
  const routes: Route[] = [];
  const channel = diagnostics_channel.channel("fastify.initialization");
  const onInit = (message: unknown) => {
    const instance = (message as { fastify: FastifyInstance }).fastify;
    instance.addHook("onRoute", (opts) => {
      for (const method of [opts.method].flat()) routes.push({ method: String(method), url: opts.url });
    });
  };
  channel.subscribe(onInit);
  try {
    const app = testApp(testDb());
    return { app, routes };
  } finally {
    channel.unsubscribe(onInit);
  }
}

const concrete = (url: string) => url.replace(/:[A-Za-z_]+/g, "x").replace(/\*/g, "x");

test("каждый маршрут API без токена мастера отвечает 401, кроме явного списка открытых", async () => {
  const { app, routes } = collectRoutes();
  await app.ready();
  const api = routes.filter((r) => r.url.startsWith("/api/") && r.method !== "HEAD" && r.method !== "OPTIONS");
  assert.ok(api.length > 60, `маршрутов API найдено ${api.length} — перечисление сломалось?`);

  const open: string[] = [];
  const unprotected: string[] = [];
  for (const r of api) {
    const key = `${r.method} ${r.url}`;
    const res = await app.inject({ method: r.method as "GET", url: concrete(r.url), payload: r.method === "GET" || r.method === "DELETE" ? undefined : {} });
    if (key in OPEN) {
      open.push(key);
      continue;
    }
    const allowed = BODY_FIRST(r) ? [400, 401] : [401];
    if (!allowed.includes(res.statusCode)) unprotected.push(`${key} → ${res.statusCode}`);
  }
  assert.deepEqual(unprotected, [], "эти маршруты ответили без токена мастера — забыт requireMaster, либо добавьте в OPEN с причиной");
  assert.deepEqual(open.sort(), Object.keys(OPEN).sort(), "в OPEN есть маршрут, которого больше нет в приложении — уберите запись");
  await app.close();
});

test("маршруты по секрету игры: без секрета при заданном GAME_SECRET — 401", async () => {
  const { app } = collectRoutes();
  await app.ready();
  const prev = process.env.GAME_SECRET;
  process.env.GAME_SECRET = "route-test-secret";
  try {
    for (const key of GAME_SECRET_ROUTES) {
      const [method, url] = key.split(" ");
      const res = await app.inject({ method: method as "POST", url, payload: { records: [] } });
      assert.equal(res.statusCode, 401, key);
    }
  } finally {
    if (prev === undefined) delete process.env.GAME_SECRET;
    else process.env.GAME_SECRET = prev;
    await app.close();
  }
});
