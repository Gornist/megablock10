import { test } from "node:test";
import assert from "node:assert/strict";
import { humanizeChange, containerIdOf, type ChangeRowLike, type HumanizeContext } from "./lib/humanize.js";
import { loginAs, testApp, testDb, testDevice, testMaster } from "./testUtil.js";

const ctx: HumanizeContext = {
  playerName: (k) => ({ A: "Alice", B: "Bob" })[k] ?? k,
  containerName: (id) => (id === "arasaka-404" ? "Арасака-404" : null),
  peerName: (_ref, subject) => (subject === "A" ? "Bob" : "Alice"),
  itemTitle: (_s, _f, id) => (id === "d1" ? "Black Curtain" : id === "s1" ? "Кибер-тело К-7" : null),
};
const row = (over: Partial<ChangeRowLike>): ChangeRowLike => ({
  subject_key: "A", field: "balance", old_value: null, new_value: null, reason: "TRANSFER_OUT", source_ref: null, actor: "A", ...over,
});

const cases: [string, Partial<ChangeRowLike>, string, string][] = [
  ["перевод: отправка", { field: "balance", reason: "TRANSFER_OUT", old_value: "1000", new_value: "900" }, "money", "перевод 100 €$ → Bob"],
  ["перевод: получение", { subject_key: "B", field: "balance", reason: "TRANSFER_IN", old_value: "0", new_value: "100", actor: "A" }, "money", "получен перевод 100 €$ от Alice"],
  ["перевод: отмена", { field: "balance", reason: "TRANSFER_CANCELLED", old_value: "900", new_value: "1000" }, "money", "перевод 100 €$ отменён отправителем, деньги вернулись"],
  ["эдди за взлом", { field: "balance", reason: "BREACH_EDDIES", old_value: "350", new_value: "384", source_ref: "arasaka-404:9911" }, "money", "+34 €$ за взлом узла «Арасака-404»"],
  ["правка мастера: баланс", { field: "balance", reason: "MASTER_OVERRIDE", old_value: "300", new_value: "777", source_ref: "компенсация" }, "master", "мастер изменил баланс: 300 → 777. Основание: компенсация"],
  ["RAM", { field: "ramCapacity", reason: "RAM_UPGRADE", old_value: "6", new_value: "9" }, "system", "буфер RAM 6 → 9 (улучшение деки)"],
  ["создание персонажа", { field: "callsign", reason: "CHARACTER_CREATED", new_value: "Alice" }, "system", "создан персонаж, позывной «Alice»"],
  ["демон: получен", { field: "daemons.add", reason: "ITEM_TRANSFER_IN", subject_key: "B", new_value: '{"daemonId":"d1","name":"Black Curtain","tier":"2"}' }, "item", "получен демон «Black Curtain» от Alice"],
  ["демон: передан (имя по истории)", { field: "daemons.remove", reason: "ITEM_TRANSFER_OUT", new_value: '{"daemonId":"d1"}' }, "item", "демон «Black Curtain» передан → Bob"],
  ["шард: добыт", { field: "shards.add", reason: "BREACH_LOOT", new_value: '{"title":"Кибер-тело К-7","tier":"2","decrypted":false}', source_ref: "shard:arasaka-404#0" }, "item", "извлечён шард «Кибер-тело К-7» (тир 2, зашифрован) с узла «Арасака-404»"],
  ["шард: расшифрован", { field: "shards.decrypt", reason: "SHARD_DECRYPT", new_value: '{"shardId":"s1"}' }, "item", "расшифрован шард «Кибер-тело К-7»"],
  ["взлом", { field: "counters.breach", reason: "BREACH_ATTEMPT", new_value: '{"tier":"HARD","outcome":"success"}', source_ref: "arasaka-404:12345" }, "breach", "взлом узла «Арасака-404» (сложный) — успех"],
  ["взлом отклонён", { field: "counters.blocked", reason: "BREACH_BLOCKED", new_value: '{"reason":"COOLDOWN"}', source_ref: "arasaka-404" }, "breach", "попытка взлома узла «Арасака-404» отклонена: узел остывает после прошлого взлома"],
  ["сигнал СБ подавлен", { field: "counters.alert", reason: "ALERT_SUPPRESSED", new_value: '{"suppressed":true}', source_ref: "arasaka-404" }, "alert", "сигнал СБ по узлу «Арасака-404» не отправлен (подавлен демоном или узел свой)"],
  ["неизвестный узел — показываем id, а не «undefined»", { field: "counters.breach", reason: "BREACH_ATTEMPT", new_value: '{"tier":"BASE","outcome":"fail"}', source_ref: "mystery:1" }, "breach", "взлом узла «mystery» (базовый) — провал"],
];

for (const [name, over, kind, body] of cases) {
  test(`humanize: ${name}`, () => {
    const h = humanizeChange(row(over), ctx);
    assert.equal(h.body, body);
    assert.equal(h.kind, kind);
    assert.ok(!/undefined|null|\[object/.test(h.body), "в тексте не должно быть служебных значений");
  });
}

test("containerIdOf понимает все виды source_ref", () => {
  assert.equal(containerIdOf("arasaka-404:9911"), "arasaka-404");
  assert.equal(containerIdOf("shard:arasaka-404#0"), "arasaka-404");
  assert.equal(containerIdOf("daemon:x#1"), "x");
  assert.equal(containerIdOf(null), null);
});

test("API: лента и история отдают человеческую фразу, ключи в переводах заменены позывными", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const headers = { authorization: `Bearer ${await loginAs(app, master.name, master.token)}` };
  const alice = testDevice();
  const bob = testDevice();
  await app.inject({
    method: "POST", url: "/api/changes",
    payload: {
      records: [
        alice.change({ field: "callsign", oldValue: null, newValue: "Alice", reason: "CHARACTER_CREATED" }),
        bob.change({ field: "callsign", oldValue: null, newValue: "Bob", reason: "CHARACTER_CREATED" }),
        alice.change({ field: "balance", oldValue: "500", newValue: "400", reason: "TRANSFER_OUT", sourceRef: "tx-h" }),
        bob.change({ field: "balance", oldValue: "0", newValue: "100", reason: "TRANSFER_IN", sourceRef: "tx-h", actor: alice.publicKeyB64 }),
      ],
    },
  });

  const recent = (await app.inject({ method: "GET", url: "/api/changes/recent?since=0", headers })).json();
  const out = recent.records.find((r: { reason: string }) => r.reason === "TRANSFER_OUT");
  assert.equal(out.human.subject, "Alice");
  assert.equal(out.human.body, "перевод 100 €$ → Bob");

  const history = (await app.inject({ method: "GET", url: `/api/players/${encodeURIComponent(bob.publicKeyB64)}/history`, headers })).json();
  assert.ok(history.records.some((r: { human: { body: string } }) => r.human.body === "получен перевод 100 €$ от Alice"));

  const transfers = (await app.inject({ method: "GET", url: "/api/transfers", headers })).json();
  assert.equal(transfers[0].fromName, "Alice");
  assert.equal(transfers[0].toName, "Bob");
});
