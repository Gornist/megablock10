import { test } from "node:test";
import assert from "node:assert/strict";
import { buildApp } from "./app.js";
import { testDb } from "./testUtil.js";

/**
 * Глобальный error handler (см. app.ts): 5xx прячет message (могут утечь детали БД
 * на /api/changes — доступен любому устройству в сети без авторизации мастера),
 * 4xx — оставляет как есть (это уже безопасные сообщения самого Fastify/роута).
 */
test("необработанное исключение с 5xx отдаёт общее сообщение, не message ошибки", async () => {
  const app = buildApp(testDb(), { logger: false });
  app.get("/__boom", async () => {
    throw new Error("секретная деталь: таблица transactions, колонка counterpartyPubKeyB64");
  });
  const res = await app.inject({ method: "GET", url: "/__boom" });
  assert.equal(res.statusCode, 500);
  const body = res.json();
  assert.equal(body.error, "internal error");
  assert.ok(!JSON.stringify(body).includes("секретная деталь"));
});

test("исключение со своим 4xx statusCode отдаёт message как есть", async () => {
  const app = buildApp(testDb(), { logger: false });
  app.get("/__bad", async () => {
    const err = Object.assign(new Error("плохой запрос: поле обязательно"), { statusCode: 400 });
    throw err;
  });
  const res = await app.inject({ method: "GET", url: "/__bad" });
  assert.equal(res.statusCode, 400);
  assert.equal(res.json().error, "плохой запрос: поле обязательно");
});

test("неизвестный маршрут по-прежнему отдаёт обычный 404, не 500", async () => {
  const app = buildApp(testDb(), { logger: false });
  const res = await app.inject({ method: "GET", url: "/api/does-not-exist" });
  assert.equal(res.statusCode, 404);
});
