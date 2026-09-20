import { test } from "node:test";
import assert from "node:assert/strict";
import { ipv4Of, resetPresence } from "./lib/presence.js";
import { testApp, testDb, testDevice } from "./testUtil.js";

const registered = async (app: ReturnType<typeof testApp>, dev: ReturnType<typeof testDevice>, name: string) =>
  app.inject({
    method: "POST",
    url: "/api/changes",
    payload: { records: [dev.change({ field: "callsign", oldValue: null, newValue: name, reason: "CHARACTER_CREATED" })] },
  });

const heartbeat = (app: ReturnType<typeof testApp>, dev: ReturnType<typeof testDevice>, ip: string, presence: unknown) =>
  app.inject({ method: "POST", url: "/api/changes", remoteAddress: ip, payload: { records: [], subjectKeyB64: dev.publicKeyB64, presence } });

test("heartbeat отдаёт остальных игроков с адресом соединения и портом — запасное обнаружение пиров", async () => {
  resetPresence();
  const app = testApp(testDb());
  const alice = testDevice(), bob = testDevice();
  await registered(app, alice, "Alice");
  await registered(app, bob, "Bob");

  await heartbeat(app, bob, "192.0.2.20", { chatPort: 40001, callsign: "Bob", faction: "Rats" });
  const res = (await heartbeat(app, alice, "192.0.2.21", { chatPort: 40002, callsign: "Alice", faction: "Neon" })).json();

  assert.deepEqual(res.peers, [{ pubKeyB64: bob.publicKeyB64, host: "192.0.2.20", port: 40001, callsign: "Bob", faction: "Rats" }]);
  const back = (await heartbeat(app, bob, "192.0.2.20", { chatPort: 40001, callsign: "Bob", faction: "Rats" })).json();
  assert.equal(back.peers.length, 1, "Боб видит Алису");
  assert.equal(back.peers[0].host, "192.0.2.21");
});

test("незнакомый ключ и битый порт не попадают в список пиров (нельзя подсунуть чужой адрес)", async () => {
  resetPresence();
  const app = testApp(testDb());
  const alice = testDevice(), bob = testDevice(), stranger = testDevice();
  await registered(app, alice, "Alice");
  await registered(app, bob, "Bob");

  await heartbeat(app, stranger, "192.0.2.99", { chatPort: 40009, callsign: "X", faction: "?" });   // нет ни одной записи
  await heartbeat(app, bob, "192.0.2.20", { chatPort: 70000, callsign: "Bob", faction: "Rats" });   // порт вне диапазона
  const res = (await heartbeat(app, alice, "192.0.2.21", { chatPort: 40002, callsign: "Alice", faction: "Neon" })).json();
  assert.deepEqual(res.peers, []);
});

test("адрес берётся из соединения, а не из тела запроса", async () => {
  resetPresence();
  const app = testApp(testDb());
  const alice = testDevice(), bob = testDevice();
  await registered(app, alice, "Alice");
  await registered(app, bob, "Bob");
  await heartbeat(app, bob, "192.0.2.20", { chatPort: 40001, callsign: "Bob", faction: "Rats", host: "6.6.6.6" });
  const res = (await heartbeat(app, alice, "192.0.2.21", { chatPort: 40002, callsign: "Alice", faction: "Neon" })).json();
  assert.equal(res.peers[0].host, "192.0.2.20");
});

test("ipv4Of: v4-mapped адрес разбирается, остальное — нет", () => {
  assert.equal(ipv4Of("::ffff:192.0.2.5"), "192.0.2.5");
  assert.equal(ipv4Of("192.0.2.5"), "192.0.2.5");
  assert.equal(ipv4Of("::1"), null);
  assert.equal(ipv4Of("999.1.1.1"), null);
  assert.equal(ipv4Of(undefined), null);
});

test("список пиров получает только известный серверу игрок — случайный ключ видит пустой список", async () => {
  resetPresence();
  const app = testApp(testDb());
  const alice = testDevice(), bob = testDevice(), stranger = testDevice();
  await registered(app, alice, "Alice");
  await registered(app, bob, "Bob");
  await heartbeat(app, bob, "192.0.2.20", { chatPort: 40001, callsign: "Bob", faction: "Rats" });

  const res = (await heartbeat(app, stranger, "192.0.2.99", { chatPort: 40009, callsign: "X", faction: "?" })).json();
  assert.deepEqual(res.peers, [], "у чужого ключа нет ни одной записи — адреса игроков ему не отдаются");
  assert.deepEqual((await app.inject({ method: "POST", url: "/api/changes", payload: { records: [] } })).json().peers, [], "без ключа — тоже пусто");

  const newcomer = testDevice();
  const first = await app.inject({
    method: "POST",
    url: "/api/changes",
    remoteAddress: "192.0.2.30",
    payload: { records: [newcomer.change({ field: "callsign", oldValue: null, newValue: "New", reason: "CHARACTER_CREATED" })], subjectKeyB64: newcomer.publicKeyB64 },
  });
  assert.equal(first.json().peers.length, 1, "новичок, приславший первые записи этим же запросом, уже известен и получает список");
});
