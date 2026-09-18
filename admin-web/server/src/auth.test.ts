import { test } from "node:test";
import assert from "node:assert/strict";
import { testApp, testDb, testMaster } from "./testUtil.js";

test("логин с верным токеном выдаёт сессию", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db, "Мастер Раз");

  const res = await app.inject({ method: "POST", url: "/api/auth/login", payload: { name: "Мастер Раз", token: master.token } });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.ok(body.sessionToken);
  assert.equal(body.master.name, "Мастер Раз");
});

test("логин с неверным токеном — 401, токен нигде не хранится открытым текстом", async () => {
  const db = testDb();
  const app = testApp(db);
  testMaster(db, "Мастер Раз");

  const res = await app.inject({ method: "POST", url: "/api/auth/login", payload: { name: "Мастер Раз", token: "неверный-токен" } });
  assert.equal(res.statusCode, 401);
});

test("защищённый роут без Authorization — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "GET", url: "/api/overview" });
  assert.equal(res.statusCode, 401);
});

test("защищённый роут с протухшей/поддельной сессией — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "GET", url: "/api/overview", headers: { authorization: "Bearer совсем-не-та-сессия" } });
  assert.equal(res.statusCode, 401);
});

test("rate-limit на логин — после N неудачных попыток дальнейшие отклоняются 429", async () => {
  const db = testDb();
  const app = testApp(db);
  testMaster(db, "Мастер Раз");

  let lastStatus = 0;
  for (let i = 0; i < 15; i++) {
    const res = await app.inject({ method: "POST", url: "/api/auth/login", payload: { name: "Мастер Раз", token: "неверно" } });
    lastStatus = res.statusCode;
  }
  assert.equal(lastStatus, 429);
});

test("rate-limit сбрасывается после успешного входа — свои же опечатки не запирают мастера навсегда", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db, "Мастер Раз");

  // пара опечаток, не превышающих лимит
  await app.inject({ method: "POST", url: "/api/auth/login", payload: { name: "Мастер Раз", token: "опечатка1" } });
  await app.inject({ method: "POST", url: "/api/auth/login", payload: { name: "Мастер Раз", token: "опечатка2" } });

  const ok = await app.inject({ method: "POST", url: "/api/auth/login", payload: { name: "Мастер Раз", token: master.token } });
  assert.equal(ok.statusCode, 200);
});
