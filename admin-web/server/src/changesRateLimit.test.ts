import { test } from "node:test";
import assert from "node:assert/strict";
import { testApp, testDb } from "./testUtil.js";

const post = (app: ReturnType<typeof testApp>, remoteAddress?: string) =>
  app.inject({ method: "POST", url: "/api/changes", remoteAddress, payload: { records: [] } });

test("/api/changes: сверх лимита на адрес — 429 с Retry-After, другой адрес не затронут", async () => {
  process.env.CHANGES_RATE_PER_MIN = "3";
  try {
    const app = testApp(testDb());
    for (let i = 0; i < 3; i++) assert.equal((await post(app, "192.0.2.10")).statusCode, 200);
    const blocked = await post(app, "192.0.2.10");
    assert.equal(blocked.statusCode, 429);
    assert.equal(blocked.headers["retry-after"], "30");
    assert.equal((await post(app, "192.0.2.11")).statusCode, 200, "лимит на адрес, а не общий");
  } finally {
    delete process.env.CHANGES_RATE_PER_MIN;
  }
});

test("/api/changes: CHANGES_RATE_PER_MIN=0 отключает лимит; по умолчанию обычная нагрузка проходит", async () => {
  process.env.CHANGES_RATE_PER_MIN = "0";
  try {
    const app = testApp(testDb());
    for (let i = 0; i < 200; i++) assert.equal((await post(app)).statusCode, 200);
  } finally {
    delete process.env.CHANGES_RATE_PER_MIN;
  }
  const app = testApp(testDb());
  for (let i = 0; i < 100; i++) assert.equal((await post(app)).statusCode, 200);
});
