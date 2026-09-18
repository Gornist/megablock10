import { test } from "node:test";
import assert from "node:assert/strict";
import { claimSignature, testApp, testDb, testDevice } from "./testUtil.js";

test("без GAME_SECRET /api/changes работает как раньше — открыт", async () => {
  delete process.env.GAME_SECRET;
  const app = testApp(testDb());
  const res = await app.inject({ method: "POST", url: "/api/changes", payload: { records: [] } });
  assert.equal(res.statusCode, 200);
});

test("с GAME_SECRET /api/changes отклоняет запрос без заголовка или с неверным значением", async () => {
  process.env.GAME_SECRET = "test-secret";
  try {
    const app = testApp(testDb());

    const noHeader = await app.inject({ method: "POST", url: "/api/changes", payload: { records: [] } });
    assert.equal(noHeader.statusCode, 401);

    const wrongHeader = await app.inject({
      method: "POST",
      url: "/api/changes",
      headers: { "x-game-secret": "неверный" },
      payload: { records: [] },
    });
    assert.equal(wrongHeader.statusCode, 401);

    const rightHeader = await app.inject({
      method: "POST",
      url: "/api/changes",
      headers: { "x-game-secret": "test-secret" },
      payload: { records: [] },
    });
    assert.equal(rightHeader.statusCode, 200);
  } finally {
    delete process.env.GAME_SECRET;
  }
});

test("с GAME_SECRET та же проверка действует и на /api/slots/:ref/claim", async () => {
  process.env.GAME_SECRET = "test-secret";
  try {
    const app = testApp(testDb());
    const device = testDevice();
    const claimedAt = Date.now();
    const signature = claimSignature(device, "container-1#0", claimedAt);

    const res = await app.inject({
      method: "POST",
      url: "/api/slots/container-1%230/claim",
      payload: { claimantKeyB64: device.publicKeyB64, claimedAt, signature },
    });
    assert.equal(res.statusCode, 401);
  } finally {
    delete process.env.GAME_SECRET;
  }
});
