import assert from "node:assert/strict";
import { buildApp } from "./app.js";
import type { Db } from "./db/index.js";
import { BridgeClient, type BridgeClientOptions } from "./net/bridgeClient.js";
import { FakeBridge, type FakeBridgeOptions } from "./net/fakeBridge.js";
import { NetService } from "./net/netService.js";
import { loginAs, testDb, testMaster } from "./testUtil.js";

/** Опрашивает условие раз в 10 мс; не дождались за ms — тест падает с понятным «не дождались: …». */
export async function waitFor(what: string, cond: () => boolean | Promise<boolean>, ms = 4000) {
  const until = Date.now() + ms;
  while (!(await cond())) {
    if (Date.now() > until) assert.fail(`не дождались: ${what}`);
    await new Promise((r) => setTimeout(r, 10));
  }
}

export interface SetupNetOptions {
  /** Настройки фейкового Моста (документы мира и т.п.). */
  bridge?: FakeBridgeOptions;
  /** Поверх настроек клиента Моста по умолчанию (быстрый реконнект для тестов). */
  client?: Partial<BridgeClientOptions>;
  /** Подключаться к Мосту сразу (по умолчанию да). Иначе — вызвать connect() самому. */
  connect?: boolean;
}

/**
 * Стенд «Сети»: фейковый Мост + клиент + NetService + коллектор с БД в памяти и вошедшим мастером.
 * `connect()` запускает NetService и ждёт связи; `cleanup()` гасит приложение и Мост.
 */
export async function setupNet(opts: SetupNetOptions = {}) {
  const bridge = new FakeBridge(opts.bridge ?? {});
  await bridge.start();
  const client = new BridgeClient({ url: bridge.url, key: "master-key", backoffMinMs: 20, backoffMaxMs: 60, requestTimeoutMs: 1500, ...opts.client });
  const net = new NetService(client);
  const db: Db = testDb();
  const app = buildApp(db, { logger: false, net });
  const master = testMaster(db, "Мастер-1");
  const headers = { authorization: `Bearer ${await loginAs(app, master.name, master.token)}` };
  const connect = async () => {
    net.start();
    await waitFor("Мост на связи", () => net.connected);
  };
  const post = (url: string, payload: unknown) => app.inject({ method: "POST", url, headers, payload: payload as object });
  const cleanup = async () => {
    await app.close();
    await bridge.stop();
  };
  if (opts.connect ?? true) await connect();
  return { bridge, client, net, db, app, headers, post, connect, cleanup };
}
