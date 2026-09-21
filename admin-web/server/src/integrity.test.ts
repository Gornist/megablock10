import { test } from "node:test";
import assert from "node:assert/strict";
import type { Db } from "./db/index.js";
import { seedPlayer, setup, type App } from "./testHelpers.js";

type Item = { kind: string; severity: string; detail: string; subjectKey?: string };

const send = (app: App, ...records: unknown[]) => app.inject({ method: "POST", url: "/api/changes", payload: { records } });
const attention = async (app: App, headers: Record<string, string>) => ((await app.inject({ method: "GET", url: "/api/attention", headers })).json().items as Item[]);
const age = (db: Db, key: string, minutes: number) =>
  db.prepare(`UPDATE changes SET received_at = ? WHERE subject_key = ? AND seq > 0 AND reason != 'CHARACTER_CREATED'`).run(Date.now() - minutes * 60_000, key);

test("целостность: честная цепочка баланса не даёт тревог", async () => {
  const { app, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 100 });
  await send(app, a.change({ field: "balance", oldValue: "100", newValue: "150", reason: "BREACH_EDDIES" }));
  const items = await attention(app, headers);
  assert.equal(items.filter((i) => i.kind === "balance_chain_break").length, 0);
});

test("целостность: разрыв цепочки oldValue → newValue виден мастеру", async () => {
  const { app, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 100 });
  await send(app, a.change({ field: "balance", oldValue: "900", newValue: "950", reason: "BREACH_EDDIES" }));
  const item = (await attention(app, headers)).find((i) => i.kind === "balance_chain_break");
  assert.ok(item);
  assert.match(item.detail, /Alice: по журналу было 100 €\$, а запись исходит из 900/);
  assert.equal(item.severity, "warn");
});

test("целостность: значение после правки мастера не считается разрывом", async () => {
  const { app, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 100 });
  await app.inject({ method: "POST", url: `/api/players/${encodeURIComponent(a.publicKeyB64)}/override`, headers, payload: { field: "balance", newValue: "500", reason: "компенсация" } });
  await send(app, a.change({ field: "balance", oldValue: "500", newValue: "520", reason: "BREACH_EDDIES" }));
  assert.equal((await attention(app, headers)).filter((i) => i.kind === "balance_chain_break").length, 0);
});

test("целостность: один платёж, полученный двумя игроками, — срочная тревога", async () => {
  const { app, headers } = await setup();
  const sender = await seedPlayer(app, { callsign: "Sender", faction: "X", balance: 300 });
  const b = await seedPlayer(app, { callsign: "Bob", faction: "X", balance: 0 });
  const c = await seedPlayer(app, { callsign: "Carol", faction: "X", balance: 0 });
  await send(app, sender.change({ field: "balance", oldValue: "300", newValue: "200", reason: "TRANSFER_OUT", sourceRef: "tx-dup-1" }));
  await send(app, b.change({ field: "balance", oldValue: "0", newValue: "100", reason: "TRANSFER_IN", sourceRef: "tx-dup-1" }));
  await send(app, c.change({ field: "balance", oldValue: "0", newValue: "100", reason: "TRANSFER_IN", sourceRef: "tx-dup-1" }));
  const item = (await attention(app, headers)).find((i) => i.kind === "duplicate_receive");
  assert.ok(item);
  assert.equal(item.severity, "crit");
  assert.match(item.detail, /Bob/);
  assert.match(item.detail, /Carol/);
});

test("целостность: отправка без получения виснет только после порога, отменённая и сведённая — нет", async () => {
  const { app, db, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 500 });
  const b = await seedPlayer(app, { callsign: "Bob", faction: "X", balance: 0 });
  const res = await send(app, a.change({ field: "balance", oldValue: "500", newValue: "400", reason: "TRANSFER_OUT", sourceRef: "tx-hang" }));
  assert.deepEqual(res.json().rejected, []);
  assert.equal((await attention(app, headers)).filter((i) => i.kind === "transfer_stuck").length, 0, "свежий перевод ещё не завис");

  age(db, a.publicKeyB64, 30);
  const stuck = (await attention(app, headers)).filter((i) => i.kind === "transfer_stuck");
  assert.equal(stuck.length, 1);
  assert.match(stuck[0].detail, /Alice: платёж 100 €\$ отправлен 30 мин назад/);

  // отмена отправителем закрывает вопрос
  await send(app, a.change({ field: "balance", oldValue: "400", newValue: "500", reason: "TRANSFER_CANCELLED", sourceRef: "tx-hang" }));
  age(db, a.publicKeyB64, 30);
  assert.equal((await attention(app, headers)).filter((i) => i.kind === "transfer_stuck").length, 0);
});

test("целостность: получение без отправки — предупреждение после порога; передача предмета считается так же", async () => {
  const { app, db, headers } = await setup();
  const b = await seedPlayer(app, { callsign: "Bob", faction: "X", balance: 0 });
  await send(app, b.change({ field: "balance", oldValue: "0", newValue: "70", reason: "TRANSFER_IN", sourceRef: "tx-orphan" }));
  await send(app, b.change({ field: "daemons.add", newValue: "{}", reason: "ITEM_TRANSFER_OUT", sourceRef: "item-1" }));
  age(db, b.publicKeyB64, 60);
  const items = (await attention(app, headers)).filter((i) => i.kind === "transfer_stuck");
  assert.equal(items.length, 2);
  assert.ok(items.some((i) => /Bob: платёж 70 €\$ получен/.test(i.detail)));
  assert.ok(items.some((i) => /передача предмета отправлен/.test(i.detail)));
});

test("целостность: крупный рост баланса по причине, не дающей денег, — срочная тревога", async () => {
  const { app, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 100 });
  await send(app, a.change({ field: "balance", oldValue: "100", newValue: "5100", reason: "RAM_UPGRADE" }));
  const item = (await attention(app, headers)).find((i) => i.kind === "balance_unexplained");
  assert.ok(item);
  assert.equal(item.severity, "crit");
  assert.match(item.detail, /Alice: \+5000 €\$ по причине «Улучшение RAM»/);
});

test("целостность: давние находки выпадают из окна", async () => {
  const { app, db, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 100 });
  await send(app, a.change({ field: "balance", oldValue: "900", newValue: "950", reason: "BREACH_EDDIES" }));
  age(db, a.publicKeyB64, 60 * 24);
  assert.equal((await attention(app, headers)).filter((i) => i.kind === "balance_chain_break").length, 0);
});
