import { test } from "node:test";
import assert from "node:assert/strict";
import { claimSignature, loginAs, testApp, testDb, testDevice, testMaster } from "./testUtil.js";

async function seedContainer(app: ReturnType<typeof testApp>, session: string) {
  await app.inject({
    method: "POST",
    url: "/api/containers",
    headers: { authorization: `Bearer ${session}` },
    payload: {
      containers: [
        {
          id: "nasos-4",
          name: "Насосная-4",
          tier: "HARD",
          ownerFaction: "NEON_DRAGONS",
          slots: [
            { index: 0, type: "SHARD", tier: "HARD", copies: 1, title: "Логи СБ" },
            { index: 1, type: "DAEMON", tier: "BASE", copies: 0, title: "Mainframe" },
          ],
        },
      ],
    },
  });
}

test("POST /api/slots/:ref/claim — единственный претендент получает уникальный слот", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  await seedContainer(app, session);

  const alice = testDevice();
  const claimedAt = Date.now();
  const res = await app.inject({
    method: "POST",
    url: "/api/slots/nasos-4%230/claim",
    payload: { claimantKeyB64: alice.publicKeyB64, claimedAt, signature: claimSignature(alice, "nasos-4#0", claimedAt) },
  });

  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.json(), { granted: true, copiesLeft: 0 });
});

test("POST /api/slots/:ref/claim — второй претендент на исчерпанный слот получает EXHAUSTED", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  await seedContainer(app, session);

  const alice = testDevice();
  const bob = testDevice();
  const t1 = Date.now();
  await app.inject({
    method: "POST",
    url: "/api/slots/nasos-4%230/claim",
    payload: { claimantKeyB64: alice.publicKeyB64, claimedAt: t1, signature: claimSignature(alice, "nasos-4#0", t1) },
  });

  const t2 = Date.now();
  const res = await app.inject({
    method: "POST",
    url: "/api/slots/nasos-4%230/claim",
    payload: { claimantKeyB64: bob.publicKeyB64, claimedAt: t2, signature: claimSignature(bob, "nasos-4#0", t2) },
  });

  assert.deepEqual(res.json(), { granted: false, reason: "EXHAUSTED" });
});

test("POST /api/slots/:ref/claim — тот же претендент повторно получает granted (идемпотентно, не занимает второй экземпляр)", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  await seedContainer(app, session);

  const alice = testDevice();
  const t1 = Date.now();
  await app.inject({
    method: "POST",
    url: "/api/slots/nasos-4%230/claim",
    payload: { claimantKeyB64: alice.publicKeyB64, claimedAt: t1, signature: claimSignature(alice, "nasos-4#0", t1) },
  });
  const t2 = Date.now();
  const res = await app.inject({
    method: "POST",
    url: "/api/slots/nasos-4%230/claim",
    payload: { claimantKeyB64: alice.publicKeyB64, claimedAt: t2, signature: claimSignature(alice, "nasos-4#0", t2) },
  });

  assert.deepEqual(res.json(), { granted: true, copiesLeft: 0 });
});

test("POST /api/slots/:ref/claim — бесконечный слот (copies=0) сервер не арбитрирует, выдаётся всегда", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  await seedContainer(app, session);

  const alice = testDevice();
  const bob = testDevice();
  for (const p of [alice, bob]) {
    const t = Date.now();
    const res = await app.inject({
      method: "POST",
      url: "/api/slots/nasos-4%231/claim",
      payload: { claimantKeyB64: p.publicKeyB64, claimedAt: t, signature: claimSignature(p, "nasos-4#1", t) },
    });
    assert.deepEqual(res.json(), { granted: true, copiesLeft: null });
  }
});

test("POST /api/slots/:ref/claim — отклоняет подделанную подпись", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  await seedContainer(app, session);

  const alice = testDevice();
  const mallory = testDevice();
  const claimedAt = Date.now();
  const res = await app.inject({
    method: "POST",
    url: "/api/slots/nasos-4%230/claim",
    // подпись Маллори, но claimant выдаёт себя за Алису
    payload: { claimantKeyB64: alice.publicKeyB64, claimedAt, signature: claimSignature(mallory, "nasos-4#0", claimedAt) },
  });
  assert.equal(res.statusCode, 400);
});

test("GET /api/slots и POST revoke/restore — реестр отражает аннулирование и возврат в оборот", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  await seedContainer(app, session);
  const auth = { authorization: `Bearer ${session}` };

  const alice = testDevice();
  const claimedAt = Date.now();
  await app.inject({
    method: "POST",
    url: "/api/slots/nasos-4%230/claim",
    payload: { claimantKeyB64: alice.publicKeyB64, claimedAt, signature: claimSignature(alice, "nasos-4#0", claimedAt) },
  });

  const registryBefore = (await app.inject({ method: "GET", url: "/api/slots", headers: auth })).json();
  assert.equal(registryBefore[0].copiesClaimed, 1);

  await app.inject({
    method: "POST",
    url: "/api/slots/nasos-4%230/revoke",
    headers: auth,
    payload: { claimantKeyB64: alice.publicKeyB64, reason: "тестовое аннулирование" },
  });
  const registryAfterRevoke = (await app.inject({ method: "GET", url: "/api/slots", headers: auth })).json();
  assert.equal(registryAfterRevoke[0].copiesClaimed, 0);

  // после revoke слот снова свободен для нового claim
  const bob = testDevice();
  const t2 = Date.now();
  const reclaim = await app.inject({
    method: "POST",
    url: "/api/slots/nasos-4%230/claim",
    payload: { claimantKeyB64: bob.publicKeyB64, claimedAt: t2, signature: claimSignature(bob, "nasos-4#0", t2) },
  });
  assert.equal(reclaim.json().granted, true);
});

test("POST claim — заявитель с аннулированной заявкой получает слот снова и он учитывается в реестре (без выдачи сверх тиража)", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  await seedContainer(app, session);
  const auth = { authorization: `Bearer ${session}` };

  const alice = testDevice();
  const claim = async (dev: ReturnType<typeof testDevice>) => {
    const at = Date.now();
    return (
      await app.inject({
        method: "POST",
        url: "/api/slots/nasos-4%230/claim",
        payload: { claimantKeyB64: dev.publicKeyB64, claimedAt: at, signature: claimSignature(dev, "nasos-4#0", at) },
      })
    ).json();
  };

  assert.equal((await claim(alice)).granted, true);
  await app.inject({
    method: "POST",
    url: "/api/slots/nasos-4%230/revoke",
    headers: auth,
    payload: { claimantKeyB64: alice.publicKeyB64, reason: "тест" },
  });

  assert.equal((await claim(alice)).granted, true);
  const registry = (await app.inject({ method: "GET", url: "/api/slots", headers: auth })).json();
  assert.equal(registry[0].copiesClaimed, 1, "повторная заявка Алисы должна быть учтена, а не потеряна");

  const bob = testDevice();
  assert.equal((await claim(bob)).granted, false, "слот единственный — второму претенденту не должен достаться");
});
