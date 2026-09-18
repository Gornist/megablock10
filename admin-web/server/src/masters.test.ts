import { test } from "node:test";
import assert from "node:assert/strict";
import { loginAs, testApp, testDb, testMaster } from "./testUtil.js";

async function auth(app: ReturnType<typeof testApp>, db: ReturnType<typeof testDb>, name = "Мастер Раз") {
  const master = testMaster(db, name);
  const session = await loginAs(app, master.name, master.token);
  return { authorization: `Bearer ${session}` };
}

test("GET /api/masters — список мастеров без токенов", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({ method: "GET", url: "/api/masters", headers });
  assert.equal(res.statusCode, 200);
  const list = res.json();
  assert.equal(list.length, 1);
  assert.equal(list[0].name, "Мастер Раз");
  assert.equal("token" in list[0], false, "токен не должен светиться в списке");
  assert.equal("token_hash" in list[0], false);
});

test("POST /api/masters — создаёт нового мастера, токен виден только в ответе на создание", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({ method: "POST", url: "/api/masters", headers, payload: { name: "Мастер Два" } });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.name, "Мастер Два");
  assert.ok(typeof body.token === "string" && body.token.length > 0);

  // новый мастер реально может залогиниться своим токеном
  const login = await app.inject({ method: "POST", url: "/api/auth/login", payload: { name: "Мастер Два", token: body.token } });
  assert.equal(login.statusCode, 200);
});

test("POST /api/masters — имя уже занято — 409", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({ method: "POST", url: "/api/masters", headers, payload: { name: "Мастер Раз" } });
  assert.equal(res.statusCode, 409);
});

test("POST /api/masters — пустое имя — 400", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({ method: "POST", url: "/api/masters", headers, payload: { name: "   " } });
  assert.equal(res.statusCode, 400);
});

test("GET /api/masters — без мастерского токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "GET", url: "/api/masters" });
  assert.equal(res.statusCode, 401);
});

test("POST /api/masters — без мастерского токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "POST", url: "/api/masters", payload: { name: "X" } });
  assert.equal(res.statusCode, 401);
});
